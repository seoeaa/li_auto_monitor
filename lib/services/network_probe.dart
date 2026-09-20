import 'dart:async';
import 'dart:convert';
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
      // Preserve an actual server response, even an error; do not search for a
      // different IP with a more convenient status code.
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
    RawSocket? socket;
    RawSecureSocket? secureSocket;
    ConnectionTask<RawSocket>? task;
    final stageWatch = Stopwatch()..start();

    void close() {
      if (closed) return;
      closed = true;
      task?.cancel();
      if (secureSocket != null) _closeSocket(secureSocket!);
      // Keep the raw TCP socket: closing a detached high-level Socket does not
      // cancel a SecureSocket.secure handshake in progress.
      if (socket != null) _closeSocket(socket!);
    }

    final removeCancel = cancellation.onCancel(close);

    try {
      if (closed) throw const CheckCancelled();
      final connecting = RawSocket.startConnect(address, port)
          .then((value) {
            task = value;
            if (closed) value.cancel();
            return value.socket;
          })
          .then((value) {
            if (closed) {
              _closeSocket(value);
              throw const CheckCancelled();
            }
            socket = value;
            return value;
          });
      final value = await cancellation.wait(connecting, timeout: remaining());
      resolvedIp = value.remoteAddress.address;
      steps[1] = CheckStep(
        CheckState.success,
        'TCP: соединение с $resolvedIp:$port.',
        milliseconds: stageWatch.elapsedMilliseconds,
      );
      activeStage = 2;
      stageWatch.reset();
      final securing =
          RawSecureSocket.secure(
            value,
            host: host,
            context: securityContext,
            supportedProtocols: const ['http/1.1'],
          ).then((value) {
            if (closed) {
              _closeSocket(value);
              throw const CheckCancelled();
            }
            secureSocket = value;
            return value;
          });
      final secured = await cancellation.wait(securing, timeout: remaining());
      steps[2] = CheckStep(
        CheckState.success,
        'TLS: сертификат и имя $host проверены.',
        milliseconds: stageWatch.elapsedMilliseconds,
      );
      activeStage = 3;
      stageWatch.reset();
      final uri = Uri(scheme: 'https', host: host, port: port, path: path);
      statusCode = await cancellation.wait(
        _readHead(secured, uri),
        timeout: remaining(),
      );
      steps[3] = classifyHttpStatus(
        statusCode!,
        milliseconds: stageWatch.elapsedMilliseconds,
      );
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

  // Minimal bounded HEAD exchange. TLS is negotiated above; no redirects,
  // response body or HTTP/2 are involved. Informational responses are skipped.
  Future<int> _readHead(RawSecureSocket socket, Uri uri) async {
    final requestTarget = Uri(
      path: uri.path.isEmpty ? '/' : uri.path,
    ).toString();
    final request = ascii.encode(
      'HEAD $requestTarget HTTP/1.1\r\n'
      'Host: ${uri.authority}\r\n'
      'User-Agent: LiAutoMonitor/1.1\r\n'
      'Connection: close\r\n\r\n',
    );
    final response = Completer<int>();
    var offset = 0;
    var receivedBytes = 0;
    var informational = 0;
    var buffer = '';

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!response.isCompleted) response.completeError(error, stackTrace);
    }

    void write() {
      if (response.isCompleted) return;
      while (offset < request.length) {
        final count = socket.write(request, offset);
        if (count == 0) break;
        offset += count;
      }
      socket.writeEventsEnabled = offset < request.length;
    }

    void read() {
      while (!response.isCompleted) {
        final chunk = socket.read(8192);
        if (chunk == null) break;
        receivedBytes += chunk.length;
        if (receivedBytes > 65536) {
          throw const HttpException('Заголовки больше 64 КиБ');
        }
        buffer += latin1.decode(chunk);
        while (!response.isCompleted) {
          final end = buffer.indexOf('\r\n\r\n');
          if (end < 0) break;
          final headers = buffer.substring(0, end).split('\r\n');
          buffer = buffer.substring(end + 4);
          final match = RegExp(
            r'^HTTP/1\.[01] ([1-5][0-9]{2})(?: .*)?$',
          ).firstMatch(headers.first);
          if (match == null) {
            throw const HttpException('Некорректная строка статуса HTTP');
          }
          for (final header in headers.skip(1)) {
            if (header.isNotEmpty &&
                !header.contains(':') &&
                !header.startsWith(' ') &&
                !header.startsWith('\t')) {
              throw const HttpException('Некорректный заголовок HTTP');
            }
          }
          final code = int.parse(match.group(1)!);
          if (code < 200 && code != 101) {
            if (++informational > 10) {
              throw const HttpException('Слишком много промежуточных ответов');
            }
            continue;
          }
          response.complete(code);
        }
      }
    }

    final subscription = socket.listen(
      (event) {
        try {
          if (event == RawSocketEvent.write) write();
          if (event == RawSocketEvent.read) read();
          if (event == RawSocketEvent.readClosed ||
              event == RawSocketEvent.closed) {
            fail(
              const HttpException('Соединение закрыто до получения заголовков'),
            );
          }
        } catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: () => fail(const HttpException('Нет полного ответа HTTP')),
    );
    try {
      socket.readEventsEnabled = true;
      socket.writeEventsEnabled = true;
      write();
      return await response.future;
    } finally {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
  }

  static void _closeSocket(RawSocket socket) {
    try {
      unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
    } catch (_) {
      // The other layer may already have closed the shared transport.
    }
  }

  static String _error(String stage, Object error) {
    if (error is TimeoutException) return '$stage: время ожидания истекло.';
    if (error is HandshakeException) {
      return '$stage: TLS-рукопожатие не завершено (${error.message}).';
    }
    if (error is SocketException) return '$stage: ${error.message}.';
    if (error is HttpException) return '$stage: ${error.message}.';
    return '$stage: проверка не завершена (${error.runtimeType}).';
  }
}
