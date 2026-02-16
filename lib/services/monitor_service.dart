import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';
import 'geoip_service.dart';
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
  Timer? _timer;

  static final _bracketRegex = RegExp(r'[\(\)]');

  List<HostStatus> get hosts => _hosts;
  bool get isMonitoring => _isMonitoring;

  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    notifyListeners();

    _timer = Timer.periodic(interval, (_) => _checkAllHosts());
    _checkAllHosts(); // Initial check
  }

  void stopMonitoring() {
    _timer?.cancel();
    _isMonitoring = false;
    notifyListeners();
  }

  Future<void> refreshAllHosts() async {
    await _checkAllHosts();
    notifyListeners();
  }

  Future<void> _checkAllHosts() async {
    for (var hostStatus in _hosts) {
      await _checkHost(hostStatus);
    }
  }

  Future<void> _checkHost(HostStatus status) async {
    // 1. TCP 443 Check
    status.isTcpAvailable = await _checkTcpAvailability(status.host);

    // 2. Standard Ping for RTT
    final ping = Ping(status.host, count: 1);

    try {
      PingResponse? bestResponse;

      // We listen to the stream for up to 5 seconds.
      // On some platforms (like Android), the first event might be a header or resolution event without time.
      await for (final event in ping.stream.timeout(
        const Duration(seconds: 5),
      )) {
        if (event.response != null) {
          bestResponse = event.response;
          // If we have a response with time, we found what we need.
          if (bestResponse?.time != null) break;
        }
        if (event.error != null) break;
      }

      if (bestResponse != null) {
        status.rtt = bestResponse.time?.inMilliseconds.toDouble();
        status.resolvedIp = bestResponse.ip
            ?.replaceAll(_bracketRegex, '')
            .trim();

        // Fetch GeoIP for the resolved IP
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
    } catch (_) {
      // Timeout or other error
    }

    // 3. Update overall status
    if (status.isTcpAvailable) {
      status.state = HostState.online;
      status.errorMessage = null;
    } else {
      status.state = HostState.down;
      status.errorMessage = 'Хост недоступен (TCP 443)';
    }

    status.lastChecked = DateTime.now();

    // 4. Save history
    HistoryService.saveEntry(status.host, status.isOnline);
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
        final event = await ping.stream
            .firstWhere((e) => e.response != null || e.error != null)
            .timeout(const Duration(seconds: 3));

        if (event.response != null && event.response!.ip != null) {
          final rawIp = event.response!.ip!;
          final ip = rawIp.replaceAll(_bracketRegex, '').trim();
          final time = event.response!.time?.inMilliseconds.toDouble() ?? 0;

          final hop = HopInfo(
            number: ttl,
            ip: ip,
            time: time > 0 ? time : null,
          );

          ipsToQuery.add(ip);
          status.updateHops((hops) => hops.add(hop));

          // If we reached the destination
          if (event.error == null) {
            break;
          }
        } else {
          status.updateHops(
            (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
          );
        }
      } catch (e) {
        status.updateHops(
          (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
        );
      }
    }

    // After tracing is done (or stopped), fetch all GeoIP data in one batch
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

  Future<bool> _checkTcpAvailability(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
