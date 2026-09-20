import 'dart:async';
import 'dart:io';
import '../models/diagnostic_result.dart';

class CheckCancelled implements Exception {
  const CheckCancelled();
}

class CheckCancellation {
  final Completer<void> _signal = Completer<void>();
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _signal.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _signal.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T> wait<T>(Future<T> operation, {Duration? timeout}) {
    final future = Future.any<T>([
      operation,
      _signal.future.then<T>((_) => throw const CheckCancelled()),
    ]);
    return timeout == null ? future : future.timeout(timeout);
  }
}

typedef AddressLookup = Future<List<InternetAddress>> Function(String host);

class NetworkProbe {
  final AddressLookup lookup;
  final Duration hostTimeout;
  final Duration stageTimeout;
  final SecurityContext? securityContext;

  NetworkProbe({
    AddressLookup? lookup,
    this.hostTimeout = const Duration(seconds: 15),
    this.stageTimeout = const Duration(seconds: 4),
    this.securityContext,
  }) : lookup = lookup ?? ((host) => InternetAddress.lookup(host));

  Future<DiagnosticResult> check(
    String host,
    CheckCancellation cancellation, {
    int port = 443,
    String path = '/',
  }) async {
    final watch = Stopwatch()..start();
    final attempts = <String>[];
    final steps = List<CheckStep>.filled(
      4,
      const CheckStep(CheckState.skipped, 'Предыдущий этап не завершён.'),
    );
    Duration remaining() {
      final left = hostTimeout - watch.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException('Лимит времени проверки');
      }
      return left < stageTimeout ? left : stageTimeout;
    }

    List<InternetAddress> addresses;
    try {
      if (cancellation.isCancelled) throw const CheckCancelled();
      addresses = await cancellation.wait(lookup(host), timeout: remaining());
      // Preserve OS preference, while avoiding duplicate address attempts.
      final seen = <String>{};
      addresses = addresses
          .where((address) => seen.add(address.address))
          .toList();
      if (addresses.isEmpty) {
        throw const SocketException('DNS не вернул адресов');
      }
      steps[0] = CheckStep(
        CheckState.success,
        'DNS: получено адресов ${addresses.length}.',
        milliseconds: watch.elapsedMilliseconds,
      );
    } on CheckCancelled {
      return DiagnosticResult(
        steps: steps,
        checkedAt: DateTime.now(),
        cancelled: true,
      );
    } catch (error) {
      steps[0] = CheckStep(CheckState.failure, _error('DNS', error));
      return DiagnosticResult(steps: steps, checkedAt: DateTime.now());
    }

    DiagnosticResult? best;
    for (final address in addresses) {
      if (cancellation.isCancelled) {
        return DiagnosticResult(
          steps: steps,
          checkedAt: DateTime.now(),
          cancelled: true,
        );
      }
      if (watch.elapsed >= hostTimeout) {
        attempts.add('Остальные адреса не проверены: исчерпан лимит времени.');
        break;
      }
      final result = await _checkAddress(
        host,
        port,
        path,
        address,
        steps[0],
        cancellation,
        remaining,
      );
      attempts.add('${address.address}: ${result.summary}');
      if (result.cancelled) return result.withAttempts(attempts);
      // Never hide an HTTP error by hunting for a green response on another IP.
      if (result.httpStatusCode != null) return result.withAttempts(attempts);
      if (best == null || _progress(result) > _progress(best)) best = result;
    }
    return (best ??
            DiagnosticResult(
              steps: [
                steps[0],
                const CheckStep(
                  CheckState.failure,
                  'Исчерпан лимит времени TCP.',
                ),
                steps[2],
                steps[3],
              ],
              checkedAt: DateTime.now(),
            ))
        .withAttempts(attempts);
  }

  int _progress(DiagnosticResult result) =>
      result.steps.where((step) => step.available == true).length;

  Future<DiagnosticResult> _checkAddress(
    String host,
    int port,
    String path,
    InternetAddress address,
    CheckStep dns,
    CheckCancellation cancellation,
    Duration Function() remaining,
  ) async {
    final steps = <CheckStep>[
      dns,
      const CheckStep(CheckState.unknown, 'TCP ещё не проверялся.'),
      const CheckStep(CheckState.skipped, 'TCP не завершён.'),
      const CheckStep(CheckState.skipped, 'TLS не завершён.'),
    ];
    var activeStage = 1;
    var closed = false;
    var cancelled = false;
    String? resolvedIp;
    int? statusCode;
    Socket? socket;
    ConnectionTask<Socket>? task;
    final stageWatch = Stopwatch()..start();
    final client = HttpClient(context: securityContext);
    client.findProxy = (_) => 'DIRECT';
    client.autoUncompress = false;

    void close() {
      if (closed) return;
      closed = true;
      client.close(force: true);
      task?.cancel();
      socket?.destroy();
    }

    final removeCancel = cancellation.onCancel(close);

    // A custom connectionFactory must provide its own TLS socket.
    // Pin the TCP address, then verify TLS using the original hostname/SNI.
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (closed) throw const CheckCancelled();
      final connectionTask = await Socket.startConnect(address, port);
      task = connectionTask;
      final connected = connectionTask.socket.then<Socket>((value) async {
        if (closed) {
          value.destroy();
          throw const CheckCancelled();
        }
        socket = value;
        resolvedIp = value.remoteAddress.address;
        steps[1] = CheckStep(
          CheckState.success,
          'TCP: соединение с $resolvedIp:$port.',
          milliseconds: stageWatch.elapsedMilliseconds,
        );
        activeStage = 2;
        stageWatch.reset();
        final secureSocket = await SecureSocket.secure(
          value,
          host: host,
          context: securityContext,
          supportedProtocols: const ['http/1.1'],
        );
        if (closed) {
          secureSocket.destroy();
          throw const CheckCancelled();
        }
        socket = secureSocket;
        return secureSocket;
      });
      if (closed) connectionTask.cancel();
      return ConnectionTask.fromSocket(connected, () {
        connectionTask.cancel();
        socket?.destroy();
      });
    };

    try {
      final uri = Uri(scheme: 'https', host: host, port: port, path: path);
      final request = await cancellation.wait(
        client.openUrl('HEAD', uri),
        timeout: remaining(),
      );
      steps[2] = CheckStep(
        CheckState.success,
        'TLS: сертификат и имя $host проверены.',
        milliseconds: stageWatch.elapsedMilliseconds,
      );
      activeStage = 3;
      stageWatch.reset();
      request.followRedirects = false;
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'LiAutoMonitor/1.1');
      final response = await cancellation.wait(
        request.close(),
        timeout: remaining(),
      );
      statusCode = response.statusCode;
      steps[3] = classifyHttpStatus(
        statusCode,
        milliseconds: stageWatch.elapsedMilliseconds,
      );
      // HEAD needs only headers. Do not wait for a remote body or graceful EOF.
    } on CheckCancelled {
      cancelled = true;
    } catch (error) {
      if (cancellation.isCancelled) {
        cancelled = true;
      } else {
        const names = ['DNS', 'TCP', 'TLS', 'HTTPS'];
        steps[activeStage] = CheckStep(
          CheckState.failure,
          _error(names[activeStage], error),
          milliseconds: stageWatch.elapsedMilliseconds,
        );
      }
    } finally {
      removeCancel();
      close();
    }
    return DiagnosticResult(
      steps: steps,
      checkedAt: DateTime.now(),
      resolvedIp: resolvedIp,
      addressFamily: address.type == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4',
      httpStatusCode: statusCode,
      cancelled: cancelled,
    );
  }

  static String _error(String stage, Object error) {
    if (error is TimeoutException) return '$stage: время ожидания истекло.';
    if (error is HandshakeException) {
      return '$stage: TLS-рукопожатие не завершено (${error.message}).';
    }
    if (error is SocketException) return '$stage: ${error.message}.';
    return '$stage: проверка не завершена (${error.runtimeType}).';
  }
}
