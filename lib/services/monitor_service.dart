import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';
import '../config/hosts_config.dart';
import '../utils/logger.dart';
import 'history_service.dart';
import 'network_probe.dart';
import 'geoip_service.dart';

class MonitorService extends ChangeNotifier {
  late final List<HostStatus> _hosts;
  final NetworkProbe _probe;
  final List<String> _controlHosts;
  final bool _ownsHosts;
  bool _isMonitoring = false;
  bool _isCheckInProgress = false;
  bool _disposed = false;
  bool? _internetAvailable;
  bool? _dnsAvailable;
  DateTime? _lastCycleCompleted;
  Timer? _timer;
  Future<void>? _activeCycle;
  CheckCancellation? _cycleCancellation;
  Duration _interval = const Duration(seconds: 30);
  String? _sessionId;
  String? historyError;
  final Map<HostStatus, CheckCancellation> _traces = {};
  static const int _parallelChecks = 3;
  static int _sessionCounter = 0;
  static final _bracketRegex = RegExp(r'[\(\)]');

  MonitorService({
    List<HostStatus>? initialHosts,
    NetworkProbe? probe,
    List<String> controlHosts = const ['example.com', 'www.cloudflare.com'],
  }) : _probe = probe ?? NetworkProbe(),
       _controlHosts = List.unmodifiable(controlHosts),
       _ownsHosts = initialHosts == null {
    _hosts =
        initialHosts ??
        HostsConfig.defaultHosts
            .map(
              (h) => HostStatus(
                category: h['category']!,
                name: h['name']!,
                host: h['host']!,
                isOptional: h['optional'] == 'true',
              ),
            )
            .toList();
    for (final host in _hosts) {
      host.addListener(_notify);
    }
  }

  List<HostStatus> get hosts => List.unmodifiable(_hosts);
  List<HostStatus> get primaryHosts =>
      _hosts.where((host) => !host.isOptional).toList();
  bool get isMonitoring => _isMonitoring;
  bool get isCheckInProgress => _isCheckInProgress;
  bool? get internetAvailable => _internetAvailable;
  bool? get dnsAvailable => _dnsAvailable;
  DateTime? get lastCycleCompleted => _lastCycleCompleted;

  HostState get overallState =>
      aggregateHostStates(primaryHosts.map((host) => host.state));

  String get diagnosisTitle => switch (overallState) {
    HostState.online => 'Сетевая доступность подтверждена',
    HostState.degraded => 'Ответы серверов требуют внимания',
    HostState.down => 'Соединение с адресами не установлено',
    HostState.checking => 'Выполняется диагностика',
    HostState.unknown => 'Недостаточно данных для вывода',
  };

  String get diagnosisDetails {
    if (_isCheckInProgress) {
      return 'Проверяем адреса с этого устройства. До завершения показаны последние результаты.';
    }
    if (_lastCycleCompleted == null) {
      return 'Запустите проверку сетевого доступа.';
    }
    final hasSecureEvidence = _hosts.any(
      (host) => host.diagnosticResult?.hasSecureEvidence == true,
    );
    final prefix = hasSecureEvidence
        ? 'Защищённые соединения устанавливаются. '
        : 'Неудача контрольных соединений не доказывает отсутствие интернета. ';
    return '$prefixОткройте замечания в карточках. Авторизация, команды и соединение самого автомобиля не проверялись.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    if (_disposed || _isMonitoring) return;
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
    _interval = interval;
    _isMonitoring = true;
    _sessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_sessionCounter}';
    if (_cycleCancellation?.isCancelled == true && _activeCycle != null) {
      unawaited(
        _activeCycle!.then((_) {
          if (_isMonitoring && !_disposed) unawaited(_checkAllHosts());
        }),
      );
    } else {
      unawaited(_checkAllHosts());
    }
    _notify();
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _isMonitoring = false;
    _sessionId = null;
    _cycleCancellation?.cancel();
    for (final token in _traces.values) {
      token.cancel();
    }
    unawaited(
      HistoryService.flush().catchError((Object error) {
        AppLogger.error('History flush failed', error: error);
      }),
    );
    _notify();
  }

  Future<void> refreshAllHosts() => _checkAllHosts();

  Future<void> _checkAllHosts() {
    if (_disposed) return Future.value();
    if (_activeCycle != null) return _activeCycle!;
    _timer?.cancel();
    final completer = Completer<void>();
    _activeCycle = completer.future;
    _isCheckInProgress = true;
    final cancellation = CheckCancellation();
    _cycleCancellation = cancellation;
    final sessionId =
        _sessionId ??
        '${DateTime.now().microsecondsSinceEpoch}-${++_sessionCounter}';
    final watchdog = Timer(const Duration(seconds: 60), cancellation.cancel);
    _notify();
    unawaited(() async {
      try {
        await _runCycle(cancellation, sessionId);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Monitoring cycle failed',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        watchdog.cancel();
        _isCheckInProgress = false;
        _activeCycle = null;
        if (!_disposed) {
          for (final host in _hosts) {
            if (host.isChecking) host.cancelCheck();
          }
          if (_isMonitoring) {
            _timer = Timer(_interval, () => unawaited(_checkAllHosts()));
          }
          _notify();
        }
        completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _runCycle(
    CheckCancellation cancellation,
    String sessionId,
  ) async {
    final results = <DiagnosticResult>[];
    final observations = <HistoryEntry>[];
    var next = 0;
    final total = _hosts.length + _controlHosts.length;
    Future<void> worker() async {
      while (!cancellation.isCancelled && !_disposed && next < total) {
        final index = next++;
        if (index < _hosts.length) {
          final status = _hosts[index];
          status.beginCheck();
          try {
            final result = await cancellation.wait(
              _probe.check(status.host, cancellation),
            );
            if (_disposed || cancellation.isCancelled || result.cancelled) {
              continue;
            }
            status.applyResult(result);
            results.add(result);
            observations.add(
              HistoryEntry(
                host: status.host,
                timestamp: result.checkedAt,
                state: result.state,
                sessionId: sessionId,
              ),
            );
          } on CheckCancelled {
            if (!_disposed) status.cancelCheck();
          } catch (error) {
            if (!_disposed) status.cancelCheck();
            AppLogger.error('Host check failed: ${status.host}', error: error);
          }
        } else {
          try {
            final result = await cancellation.wait(
              _probe.check(_controlHosts[index - _hosts.length], cancellation),
            );
            if (!result.cancelled) results.add(result);
          } on CheckCancelled {
            break;
          } catch (error) {
            AppLogger.debug('Control check failed: $error');
          }
        }
      }
    }

    await Future.wait(List.generate(_parallelChecks, (_) => worker()));
    if (_disposed || cancellation.isCancelled) return;
    // Positive evidence from Li Auto outweighs failure of external control hosts.
    // A failed set of probes alone is not proof that the entire internet is down.
    _internetAvailable = results.any((result) => result.hasSecureEvidence)
        ? true
        : null;
    _dnsAvailable = results.isEmpty
        ? null
        : results.any((result) => result.steps[0].available == true);
    _lastCycleCompleted = DateTime.now();
    try {
      await HistoryService.saveObservations(observations);
      historyError = null;
    } catch (error) {
      historyError = 'История не сохранена: $error';
      AppLogger.error('History save failed', error: error);
    }
    if (!_disposed && !cancellation.isCancelled) {
      await _enrichLocations(cancellation);
    }
  }

  Future<void> _enrichLocations(
    CheckCancellation cancellation, {
    HostStatus? tracedHost,
  }) async {
    final targets = tracedHost == null ? _hosts : [tracedHost];
    final addresses = {for (final host in targets) host: host.resolvedIp};
    final geo = await GeoIPService.getBatchLocation([
      ...addresses.values,
      if (tracedHost != null) ...tracedHost.hops.map((hop) => hop.ip),
    ], cancellation: cancellation);
    if (_disposed || cancellation.isCancelled) return;
    for (final host in targets) {
      if (host.resolvedIp == addresses[host]) {
        final country = geo[host.resolvedIp]?['country'];
        if (country != null) host.resolvedCountry = country;
      }
    }
    if (tracedHost != null && geo.isNotEmpty) {
      tracedHost.updateHops((hops) {
        for (final hop in hops) {
          final metadata = geo[hop.ip];
          if (metadata != null) {
            hop.country = metadata['country'];
            hop.isp = metadata['isp'];
          }
        }
      });
    }
  }

  Future<void> traceHost(HostStatus status) async {
    if (_disposed || _traces.containsKey(status)) return;
    final cancellation = CheckCancellation();
    _traces[status] = cancellation;
    status.traceMessage =
        'ICMP-маршрут. Отсутствие ответа узла не доказывает блокировку.';
    status.hops = [];
    status.isTracing = true;
    final watchdog = Timer(const Duration(seconds: 65), cancellation.cancel);
    try {
      var target = InternetAddress.tryParse(status.resolvedIp ?? '');
      target ??= (await cancellation.wait(
        _probe.lookup(status.host),
        timeout: const Duration(seconds: 4),
      )).firstOrNull;
      if (target == null) throw const SocketException('Нет IP для трассировки');
      if (target.type != InternetAddressType.IPv4) {
        throw UnsupportedError(
          'Этот ICMP-адаптер не проверяет IPv6. HTTPS-проверка IPv6 поддерживается.',
        );
      }
      status.traceMessage =
          'ICMP до ${target.address}. Молчание узла не означает блокировку.';
      for (var ttl = 1; ttl <= 20 && !cancellation.isCancelled; ttl++) {
        // Construct inside try: unsupported platforms may throw before streaming.
        final ping = Ping(target.address, count: 1, ttl: ttl, timeout: 2);
        final removeCancel = cancellation.onCancel(
          () => unawaited(_stopPing(ping)),
        );
        PingResponse? hopResponse;
        try {
          hopResponse = await cancellation.wait(
            _readHop(ping),
            timeout: const Duration(seconds: 3),
          );
        } on TimeoutException {
          // A silent hop is unknown, not a packet-loss measurement.
        } finally {
          removeCancel();
          await _stopPing(ping);
        }
        if (_disposed || cancellation.isCancelled) break;
        final ip = hopResponse?.ip?.replaceAll(_bracketRegex, '').trim();
        final time = hopResponse?.time?.inMicroseconds;
        status.updateHops(
          (hops) => hops.add(
            HopInfo(
              number: ttl,
              ip: ip,
              time: time == null ? null : time / 1000.0,
            ),
          ),
        );
        if (ip == target.address && hopResponse?.time != null) break;
      }
      if (!_disposed && !cancellation.isCancelled) {
        await _enrichLocations(cancellation, tracedHost: status);
      }
    } on CheckCancelled {
      if (!_disposed) {
        status.traceMessage =
            'Трассировка остановлена. Сохранены полученные ответы.';
      }
    } catch (error) {
      if (!_disposed) {
        status.traceMessage = 'ICMP-проверка не завершена: $error';
      }
    } finally {
      watchdog.cancel();
      _traces.remove(status);
      if (!_disposed) {
        if (cancellation.isCancelled) {
          status.traceMessage = 'Трассировка остановлена.';
        }
        status.isTracing = false;
      }
    }
  }

  void stopTrace(HostStatus status) => _traces[status]?.cancel();

  Future<PingResponse?> _readHop(Ping ping) async {
    await for (final event in ping.stream) {
      if (event.response?.ip != null) return event.response;
      if (event.summary != null) break;
    }
    return null;
  }

  Future<void> _stopPing(Ping ping) async {
    try {
      await ping.stop().timeout(const Duration(seconds: 1));
    } catch (error) {
      AppLogger.debug('Ping cleanup: $error');
    }
  }

  String generateReport() {
    final buffer = StringBuffer()
      ..writeln('Li Auto Monitor — сетевая диагностика')
      ..writeln(DateTime.now().toIso8601String())
      ..writeln(
        'Проверка с текущего устройства. Функции автомобиля не проверялись.',
      )
      ..writeln('Режим: прямое соединение; HTTP-прокси не используется.')
      ..writeln('Общий вывод: $diagnosisTitle')
      ..writeln(
        'Защищённый доступ к внешним адресам: ${_formatBool(_internetAvailable)}',
      )
      ..writeln('DNS: ${_formatBool(_dnsAvailable)}');
    const names = ['DNS', 'TCP', 'TLS', 'HTTPS'];
    for (final status in _hosts) {
      buffer
        ..writeln()
        ..writeln(
          '${status.name} (${status.host})${status.isOptional ? ' [дополнительный адрес]' : ''}',
        )
        ..writeln(
          '  Состояние: ${status.state.name}${status.isChecking ? ' (обновляется)' : ''}',
        )
        ..writeln(
          '  Измерено: ${status.lastChecked?.toIso8601String() ?? 'нет данных'}',
        );
      final steps = status.checkSteps;
      for (var i = 0; i < steps.length; i++) {
        buffer.writeln('  ${names[i]}: ${steps[i].label}. ${steps[i].detail}');
      }
      if (status.resolvedIp != null) {
        buffer.writeln(
          '  IP: ${status.resolvedIp} (${status.diagnosticResult?.addressFamily ?? 'не определено'})',
        );
      }
      for (final attempt in status.diagnosticResult?.attempts ?? <String>[]) {
        buffer.writeln('  Попытка: $attempt');
      }
      if (status.hops.isNotEmpty) {
        buffer.writeln('  ${status.traceMessage ?? 'ICMP-маршрут'}');
        for (final hop in status.hops) {
          buffer.writeln(
            '    ${hop.number}: ${hop.ip ?? 'нет ответа'} ${hop.time == null ? '' : '${hop.time} мс'}',
          );
        }
      }
    }
    if (historyError != null) buffer.writeln(historyError);
    return buffer.toString().trimRight();
  }

  String _formatBool(bool? value) => value == null
      ? 'не подтверждено'
      : value
      ? 'OK'
      : 'ошибка проверки';

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _cycleCancellation?.cancel();
    for (final token in _traces.values) {
      token.cancel();
    }
    for (final host in _hosts) {
      host.removeListener(_notify);
      if (_ownsHosts) host.dispose();
    }
    unawaited(
      HistoryService.flush().catchError((Object error) {
        AppLogger.error('History flush failed', error: error);
      }),
    );
    super.dispose();
  }
}
