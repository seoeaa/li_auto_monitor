import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';
import 'geoip_service.dart';
import '../utils/logger.dart';
import 'history_service.dart';
import '../config/hosts_config.dart';

class MonitorService extends ChangeNotifier {
  late final List<HostStatus> _hosts;

  MonitorService({List<HostStatus>? initialHosts}) {
    _hosts =
        initialHosts ??
        HostsConfig.defaultHosts
            .map(
              (h) => HostStatus.unknown(h['category']!, h['name']!, h['host']!),
            )
            .toList();
    HistoryService.init();
  }

  bool _isMonitoring = false;
  bool _isCheckInProgress = false;
  bool? _internetAvailable;
  bool? _dnsAvailable;
  DateTime? _lastCycleCompleted;
  Timer? _timer;

  static const int _parallelChecks = 3;
  static final _bracketRegex = RegExp(r'[\(\)]');

  List<HostStatus> get hosts => _hosts;
  bool get isMonitoring => _isMonitoring;
  bool get isCheckInProgress => _isCheckInProgress;
  bool? get internetAvailable => _internetAvailable;
  bool? get dnsAvailable => _dnsAvailable;
  DateTime? get lastCycleCompleted => _lastCycleCompleted;

  HostState get overallState {
    if (_isCheckInProgress &&
        _hosts.every(
          (host) =>
              host.state == HostState.unknown ||
              host.state == HostState.checking,
        )) {
      return HostState.checking;
    }

    final downCount = _hosts.where((host) => host.state == HostState.down).length;
    final degradedCount = _hosts
        .where((host) => host.state == HostState.degraded)
        .length;
    final onlineCount = _hosts
        .where((host) => host.state == HostState.online)
        .length;

    if (_internetAvailable == false && onlineCount == 0) {
      return HostState.down;
    }
    if (downCount == _hosts.length && _hosts.isNotEmpty) {
      return HostState.down;
    }
    if (downCount > 0 || degradedCount > 0) {
      return HostState.degraded;
    }
    if (onlineCount == _hosts.length && _hosts.isNotEmpty) {
      return HostState.online;
    }
    if (_isCheckInProgress) {
      return HostState.checking;
    }
    return HostState.unknown;
  }

  String get diagnosisTitle {
    switch (overallState) {
      case HostState.online:
        return 'Сервисы Li Auto доступны';
      case HostState.degraded:
        return 'Есть проблемы с сервисами Li Auto';
      case HostState.down:
        if (_internetAvailable == false) {
          return 'Нет стабильного доступа к интернету';
        }
        return 'Сервисы Li Auto недоступны';
      case HostState.checking:
        return 'Выполняется диагностика';
      case HostState.unknown:
        return 'Ожидание первой проверки';
    }
  }

  String get diagnosisDetails {
    final hasOnlineHost = _hosts.any(
      (host) => host.state == HostState.online,
    );
    if (_internetAvailable == false && !hasOnlineHost) {
      return 'Контрольное TCP-соединение с интернетом не установлено. '
          'Проверьте Wi‑Fi, мобильную сеть или VPN.';
    }

    final dnsFailures = _hosts
        .where((host) => host.isDnsAvailable == false)
        .length;
    final tcpFailures = _hosts
        .where(
          (host) =>
              host.isDnsAvailable == true && host.isTcpAvailable == false,
        )
        .length;
    final tlsFailures = _hosts
        .where(
          (host) =>
              host.isTcpAvailable && host.isTlsAvailable == false,
        )
        .length;
    final httpFailures = _hosts
        .where(
          (host) =>
              host.isTlsAvailable == true && host.isHttpAvailable == false,
        )
        .length;

    if (dnsFailures == _hosts.length && _hosts.isNotEmpty) {
      return 'DNS не разрешает адреса Li Auto. Возможна проблема DNS, '
          'фильтрация доменов или отсутствие сети.';
    }
    if (tcpFailures > 0) {
      return 'Часть адресов разрешается через DNS, но соединение с TCP 443 '
          'не устанавливается. Откройте карточку сервиса для деталей.';
    }
    if (tlsFailures > 0) {
      return 'TCP-соединение устанавливается, но TLS-рукопожатие завершается '
          'ошибкой на части сервисов.';
    }
    if (httpFailures > 0) {
      return 'Сервер доступен по TLS, но HTTPS-запрос не получил ответа.';
    }
    if (overallState == HostState.online) {
      return 'DNS, TCP 443, TLS и HTTPS отвечают. '
          'Сетевая доступность сервисов выглядит нормальной.';
    }
    if (_isCheckInProgress) {
      return 'Проверяем интернет, DNS, TCP 443, TLS и HTTPS для каждого сервиса.';
    }
    return 'Запустите или обновите мониторинг, чтобы получить диагноз.';
  }

  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    notifyListeners();

    _timer = Timer.periodic(interval, (_) {
      unawaited(_checkAllHosts());
    });
    unawaited(_checkAllHosts());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _isMonitoring = false;
    notifyListeners();
  }

  Future<void> refreshAllHosts() async {
    await _checkAllHosts();
  }

  Future<void> _checkAllHosts() async {
    if (_isCheckInProgress) return;

    _isCheckInProgress = true;
    notifyListeners();

    try {
      await _checkNetworkBaseline();

      for (int i = 0; i < _hosts.length; i += _parallelChecks) {
        final end = (i + _parallelChecks).clamp(0, _hosts.length).toInt();
        final batch = _hosts.sublist(i, end);
        await Future.wait(batch.map(_checkHost));
      }

      await HistoryService.saveSnapshot({
        for (final hostStatus in _hosts)
          hostStatus.host: hostStatus.isOnline,
      });
      _lastCycleCompleted = DateTime.now();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Monitoring cycle failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isCheckInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _checkNetworkBaseline() async {
    bool dnsAvailable = false;
    bool internetAvailable = false;

    try {
      final addresses = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 4));
      dnsAvailable = addresses.isNotEmpty;
    } catch (_) {
      dnsAvailable = false;
    }

    try {
      final socket = await Socket.connect(
        '1.1.1.1',
        443,
        timeout: const Duration(seconds: 4),
      );
      await socket.close();
      internetAvailable = true;
    } catch (_) {
      internetAvailable = false;
    }

    if (!internetAvailable && dnsAvailable) {
      try {
        final socket = await Socket.connect(
          'example.com',
          443,
          timeout: const Duration(seconds: 4),
        );
        await socket.close();
        internetAvailable = true;
      } catch (_) {
        internetAvailable = false;
      }
    }

    _dnsAvailable = dnsAvailable;
    _internetAvailable = internetAvailable;
  }

  Future<void> _checkHost(HostStatus status) async {
    status.state = HostState.checking;
    status.errorMessage = null;
    status.diagnosis = null;
    status.isDnsAvailable = null;
    status.isTcpAvailable = false;
    status.isTlsAvailable = null;
    status.isHttpAvailable = null;
    status.httpStatusCode = null;
    status.rtt = null;

    try {
      final addresses = await InternetAddress.lookup(
        status.host,
      ).timeout(const Duration(seconds: 5));

      if (addresses.isEmpty) {
        throw const SocketException('DNS returned no addresses');
      }

      status.isDnsAvailable = true;
      status.resolvedIp = addresses.first.address;
    } catch (e) {
      status.isDnsAvailable = false;
      status.state = HostState.down;
      status.errorMessage = _internetAvailable == false
          ? 'Нет общего доступа к интернету'
          : 'DNS не разрешает адрес сервиса';
      status.diagnosis =
          'Не удалось получить IP-адрес ${status.host}: $e';
      status.lastChecked = DateTime.now();
      return;
    }

    final tcpResult = await _checkTcpAvailability(status.host);
    status.isTcpAvailable = tcpResult.available;

    if (!tcpResult.available) {
      status.isTlsAvailable = false;
      status.isHttpAvailable = false;
      status.state = HostState.down;
      status.errorMessage = _internetAvailable == false
          ? 'Нет общего доступа к интернету'
          : tcpResult.error ?? 'TCP 443 недоступен';
      status.diagnosis = tcpResult.error;
      status.lastChecked = DateTime.now();
      await _updatePingMetadata(status);
      return;
    }

    final tlsResult = await _checkTlsAvailability(status.host);
    status.isTlsAvailable = tlsResult.available;

    if (!tlsResult.available) {
      status.isHttpAvailable = false;
      status.state = HostState.down;
      status.errorMessage = tlsResult.error ?? 'Ошибка TLS';
      status.diagnosis =
          'TCP 443 доступен, но защищённое TLS-соединение не установлено.';
      status.lastChecked = DateTime.now();
      await _updatePingMetadata(status);
      return;
    }

    final httpResult = await _checkHttpAvailability(status.host);
    status.isHttpAvailable = httpResult.available;
    status.httpStatusCode = httpResult.statusCode;

    if (httpResult.available) {
      status.state = HostState.online;
      status.errorMessage = null;
      status.diagnosis = httpResult.statusCode != null
          ? 'HTTPS отвечает, код ${httpResult.statusCode}.'
          : 'HTTPS отвечает.';
    } else {
      status.state = HostState.degraded;
      status.errorMessage = httpResult.error ?? 'HTTPS не получил ответа';
      status.diagnosis =
          'DNS, TCP и TLS работают, но HTTP-уровень не ответил корректно.';
    }

    status.lastChecked = DateTime.now();
    await _updatePingMetadata(status);
  }

  Future<void> _updatePingMetadata(HostStatus status) async {
    final ping = Ping(status.host, count: 1);

    try {
      PingResponse? bestResponse;

      await for (final event in ping.stream.timeout(
        const Duration(seconds: 5),
      )) {
        AppLogger.debug('Ping Event for ${status.host}: $event');
        if (event.response != null) {
          bestResponse = event.response;
          if (bestResponse?.time != null) break;
        }
        if (event.error != null) break;
      }

      if (bestResponse != null) {
        status.rtt = bestResponse.time?.inMilliseconds.toDouble();

        final pingIp = bestResponse.ip
            ?.replaceAll(_bracketRegex, '')
            .trim();
        if (pingIp != null && pingIp.isNotEmpty) {
          status.resolvedIp = pingIp;
        }
      }
    } catch (_) {
      // ICMP can be blocked even when HTTPS works, so it does not define health.
    }

    if (status.resolvedIp != null) {
      final geo = await GeoIPService.getBatchLocation([status.resolvedIp!]);
      if (geo.containsKey(status.resolvedIp)) {
        status.resolvedCountry = geo[status.resolvedIp!]!['country'];
      }
    }

    status.hops = [
      HopInfo(
        number: 1,
        ip: status.resolvedIp,
        time: status.rtt,
        country: status.resolvedCountry,
      ),
    ];
  }

  Future<void> traceHost(HostStatus status) async {
    if (status.isTracing) return;
    status.isTracing = true;
    status.hops = [];
    notifyListeners();

    final Set<String> ipsToQuery = {};

    for (int ttl = 1; ttl <= 20; ttl++) {
      if (!status.isTracing) break;

      final ping = Ping(status.host, count: 1, ttl: ttl, timeout: 2);
      try {
        PingResponse? hopResponse;

        await for (final event in ping.stream.timeout(
          const Duration(seconds: 3),
        )) {
          AppLogger.debug('Trace Event for ${status.host} (TTL $ttl): $event');

          if (event.response != null && event.response!.ip != null) {
            hopResponse = event.response;
            break;
          }

          if (event.error != null) {
            break;
          }

          if (event.summary != null) break;
        }

        if (hopResponse != null && hopResponse.ip != null) {
          final rawIp = hopResponse.ip!;
          final ip = rawIp.replaceAll(_bracketRegex, '').trim();
          final time = hopResponse.time?.inMilliseconds.toDouble() ?? 0;

          final hop = HopInfo(
            number: ttl,
            ip: ip,
            time: time > 0 ? time : null,
          );

          ipsToQuery.add(ip);
          status.updateHops((hops) => hops.add(hop));

          if (ip == status.resolvedIp) {
            break;
          }
        } else {
          status.updateHops(
            (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
          );
        }
      } catch (_) {
        status.updateHops(
          (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
        );
      }
    }

    if (ipsToQuery.isNotEmpty) {
      final geo = await GeoIPService.getBatchLocation(ipsToQuery.toList());
      for (var hop in status.hops) {
        if (hop.ip != null && geo.containsKey(hop.ip)) {
          hop.country = geo[hop.ip]!['country'];
          hop.isp = geo[hop.ip]!['isp'];
        }
      }
      notifyListeners();
    }

    status.isTracing = false;
    notifyListeners();
  }

  Future<({bool available, String? error})> _checkTcpAvailability(
    String host,
  ) async {
    try {
      final socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();
      return (available: true, error: null);
    } on TimeoutException {
      return (available: false, error: 'Таймаут TCP 443');
    } on SocketException catch (e) {
      final message = e.message.toLowerCase();
      if (message.contains('refused')) {
        return (available: false, error: 'Сервер отклонил TCP 443');
      }
      if (message.contains('timed out') || message.contains('timeout')) {
        return (available: false, error: 'Таймаут TCP 443');
      }
      return (available: false, error: 'TCP 443 недоступен: ${e.message}');
    } catch (e) {
      return (available: false, error: 'Ошибка TCP 443: $e');
    }
  }

  Future<({bool available, String? error})> _checkTlsAvailability(
    String host,
  ) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();
      return (available: true, error: null);
    } on TimeoutException {
      return (available: false, error: 'Таймаут TLS-рукопожатия');
    } on HandshakeException catch (e) {
      return (available: false, error: 'Ошибка TLS-сертификата: ${e.message}');
    } on SocketException catch (e) {
      return (available: false, error: 'Ошибка TLS: ${e.message}');
    } catch (e) {
      return (available: false, error: 'Ошибка TLS: $e');
    }
  }

  Future<
    ({bool available, int? statusCode, String? error})
  > _checkHttpAvailability(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client
          .headUrl(Uri.https(host, '/'))
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'LiAutoMonitor/1.1');

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final statusCode = response.statusCode;
      await response.drain();

      return (
        available: true,
        statusCode: statusCode,
        error: null,
      );
    } on TimeoutException {
      return (
        available: false,
        statusCode: null,
        error: 'Таймаут HTTPS',
      );
    } on HttpException catch (e) {
      return (
        available: false,
        statusCode: null,
        error: 'Ошибка HTTPS: ${e.message}',
      );
    } on SocketException catch (e) {
      return (
        available: false,
        statusCode: null,
        error: 'Ошибка HTTPS: ${e.message}',
      );
    } catch (e) {
      return (
        available: false,
        statusCode: null,
        error: 'Ошибка HTTPS: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  String generateReport() {
    final buffer = StringBuffer();
    final now = DateTime.now();

    buffer.writeln('Li Auto Monitor 1.1');
    buffer.writeln(now.toIso8601String());
    buffer.writeln();
    buffer.writeln('Общий диагноз: $diagnosisTitle');
    buffer.writeln('Интернет: ${_formatBool(_internetAvailable)}');
    buffer.writeln('DNS: ${_formatBool(_dnsAvailable)}');
    buffer.writeln();

    for (final status in _hosts) {
      buffer.writeln('${status.name} (${status.host})');
      buffer.writeln('  Состояние: ${_formatState(status.state)}');
      buffer.writeln('  DNS: ${_formatBool(status.isDnsAvailable)}');
      buffer.writeln('  TCP 443: ${_formatBool(status.isTcpAvailable)}');
      buffer.writeln('  TLS: ${_formatBool(status.isTlsAvailable)}');
      buffer.writeln(
        '  HTTPS: ${_formatBool(status.isHttpAvailable)}'
        '${status.httpStatusCode != null ? ' (${status.httpStatusCode})' : ''}',
      );
      buffer.writeln(
        '  RTT: ${status.rtt != null ? '${status.rtt!.toStringAsFixed(1)} ms' : '—'}',
      );
      if (status.resolvedIp != null) {
        buffer.writeln('  IP: ${status.resolvedIp}');
      }
      if (status.errorMessage != null) {
        buffer.writeln('  Ошибка: ${status.errorMessage}');
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  String _formatBool(bool? value) {
    if (value == null) return '—';
    return value ? 'OK' : 'FAIL';
  }

  String _formatState(HostState state) {
    switch (state) {
      case HostState.online:
        return 'ONLINE';
      case HostState.degraded:
        return 'DEGRADED';
      case HostState.down:
        return 'DOWN';
      case HostState.checking:
        return 'CHECKING';
      case HostState.unknown:
        return 'UNKNOWN';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
