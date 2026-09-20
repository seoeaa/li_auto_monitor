import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:li_auto_monitor/models/diagnostic_result.dart';
import 'package:li_auto_monitor/services/network_probe.dart';

void main() {
  late Directory directory;
  late SecurityContext serverContext;
  late SecurityContext clientContext;
  late HttpServer server;
  late Future<void> Function(HttpRequest) handler;
  late List<String> requestedHosts;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('li-auto-tls-');
    final certificate = '${directory.path}/certificate.pem';
    final key = '${directory.path}/key.pem';
    final process = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', key, '-out', certificate, '-days', '1',
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
    ]);
    expect(process.exitCode, 0, reason: process.stderr.toString());
    serverContext = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey(key);
    clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(certificate);
  });
  tearDownAll(() async => directory.delete(recursive: true));

  setUp(() async {
    requestedHosts = [];
    handler = (request) async {
      request.response.statusCode = 204;
      await request.response.close();
    };
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
    server.listen((request) {
      requestedHosts.add(request.headers.value(HttpHeaders.hostHeader) ?? '');
      unawaited(handler(request).catchError((Object _) {}));
    }, onError: (Object _) {});
  });
  tearDown(() async => server.close(force: true));

  NetworkProbe probe({AddressLookup? lookup, Duration stage = const Duration(seconds: 2), SecurityContext? trust}) =>
      NetworkProbe(
        lookup: lookup ?? ((_) async => [InternetAddress.loopbackIPv4]),
        securityContext: trust ?? clientContext,
        stageTimeout: stage,
        hostTimeout: const Duration(seconds: 5),
      );

  test('one DNS lookup, selected IP, validated hostname and original Host header', () async {
    var lookups = 0;
    final result = await probe(lookup: (host) async {
      lookups++;
      expect(host, 'localhost');
      return [InternetAddress.loopbackIPv4];
    }).check('localhost', CheckCancellation(), port: server.port);
    expect(lookups, 1);
    expect(result.state, HostState.online);
    expect(result.resolvedIp, '127.0.0.1');
    expect(result.addressFamily, 'IPv4');
    expect(result.steps.every((step) => step.state == CheckState.success), isTrue);
    expect(requestedHosts, ['localhost:${server.port}']);
    expect(result.vehicleFunctionsVerified, isFalse);
  });

  for (final code in [301, 401, 403, 404, 405, 429, 503]) {
    test('real HTTP $code remains reachable with an explicit warning', () async {
      handler = (request) async {
        request.response.statusCode = code;
        if (code == 301) request.response.headers.set(HttpHeaders.locationHeader, 'https://never-request.invalid/');
        await request.response.close();
      };
      final result = await probe().check('localhost', CheckCancellation(), port: server.port);
      expect(result.httpStatusCode, code);
      expect(result.state, HostState.degraded);
      expect(result.steps[3].available, isTrue);
      expect(requestedHosts, hasLength(1));
    });
  }

  test('a certificate for another hostname is never accepted', () async {
    final result = await probe().check('wrong.invalid', CheckCancellation(), port: server.port);
    expect(result.steps[1].state, CheckState.success);
    expect(result.steps[2].state, CheckState.failure);
    expect(result.steps[3].state, CheckState.skipped);
    expect(result.state, HostState.down);
    expect(requestedHosts, isEmpty);
  });

  test('untrusted certificate fails without any bad-certificate bypass', () async {
    final result = await probe(trust: SecurityContext(withTrustedRoots: false))
        .check('localhost', CheckCancellation(), port: server.port);
    expect(result.steps[2].state, CheckState.failure);
    expect(result.steps[3].state, CheckState.skipped);
  });

  test('DNS failure skips all dependent stages', () async {
    final result = await probe(lookup: (_) async => throw const SocketException('No address'))
        .check('localhost', CheckCancellation(), port: server.port);
    expect(result.steps[0].state, CheckState.failure);
    expect(result.steps.skip(1).every((step) => step.state == CheckState.skipped), isTrue);
    expect(result.resolvedIp, isNull);
    expect(requestedHosts, isEmpty);
  });

  test('an unavailable IPv6 address falls back to IPv4 without resolving again', () async {
    var lookups = 0;
    final result = await probe(lookup: (_) async {
      lookups++;
      return [InternetAddress.loopbackIPv6, InternetAddress.loopbackIPv4];
    }).check('localhost', CheckCancellation(), port: server.port);
    expect(lookups, 1);
    expect(result.state, HostState.online);
    expect(result.addressFamily, 'IPv4');
    expect(result.resolvedIp, '127.0.0.1');
    expect(result.attempts, hasLength(2));
  });

  test('HTTP headers timeout is bounded while TCP and TLS stay successful', () async {
    handler = (_) async {};
    final watch = Stopwatch()..start();
    final result = await probe(stage: const Duration(milliseconds: 300))
        .check('localhost', CheckCancellation(), port: server.port);
    expect(result.steps[1].state, CheckState.success);
    expect(result.steps[2].state, CheckState.success);
    expect(result.steps[3].state, CheckState.failure);
    expect(result.state, HostState.degraded);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('cancellation during stalled headers completes promptly', () async {
    final requestReceived = Completer<void>();
    handler = (_) async { if (!requestReceived.isCompleted) requestReceived.complete(); };
    final token = CheckCancellation();
    final resultFuture = probe().check('localhost', token, port: server.port);
    await requestReceived.future.timeout(const Duration(seconds: 2));
    token.cancel();
    final result = await resultFuture.timeout(const Duration(seconds: 1));
    expect(result.cancelled, isTrue);
  });

  test('late DNS completion cannot start a socket after cancellation', () async {
    final pending = Completer<List<InternetAddress>>();
    final token = CheckCancellation();
    final resultFuture = probe(lookup: (_) => pending.future).check('localhost', token, port: server.port);
    token.cancel();
    expect((await resultFuture).cancelled, isTrue);
    pending.complete([InternetAddress.loopbackIPv4]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requestedHosts, isEmpty);
  });

  test('TLS handshake timeout closes the accepted TCP socket', () async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final disconnected = Completer<void>();
    final connections = <Socket>[];
    raw.listen((socket) {
      connections.add(socket);
      socket.listen((_) {}, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      }, onError: (Object _) {
        if (!disconnected.isCompleted) disconnected.complete();
      });
    });
    try {
      final result = await probe(stage: const Duration(milliseconds: 250))
          .check('localhost', CheckCancellation(), port: raw.port);
      expect(result.steps[1].state, CheckState.success);
      expect(result.steps[2].state, CheckState.failure);
      expect(result.steps[3].state, CheckState.skipped);
      await disconnected.future.timeout(const Duration(seconds: 2));
    } finally {
      for (final socket in connections) {
        socket.destroy();
      }
      await raw.close();
    }
  });
}
