import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';
import 'geoip_service.dart';
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
      final event = await ping.stream
          .firstWhere((e) => e.response != null || e.error != null)
          .timeout(const Duration(seconds: 5));

      if (event.response != null) {
        status.rtt = event.response!.time?.inMilliseconds.toDouble();
        status.resolvedIp = event.response!.ip
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
  }

  Future<void> traceHost(HostStatus status) async {
    if (status.isTracing) return;
    status.isTracing = true;
    status.hops = [];
    notifyListeners();

    for (int ttl = 1; ttl <= 20; ttl++) {
      if (!status.isTracing) break; // Allow stopping?

      final ping = Ping(status.host, count: 1, ttl: ttl, timeout: 2);
      try {
        final event = await ping.stream
            .firstWhere((e) => e.response != null || e.error != null)
            .timeout(const Duration(seconds: 3));

        if (event.response != null && event.response!.ip != null) {
          // Clean IP from brackets if present (e.g. "(1.2.3.4)")
          final rawIp = event.response!.ip!;
          final ip = rawIp.replaceAll(_bracketRegex, '').trim();

          final time = event.response!.time?.inMilliseconds.toDouble() ?? 0;

          final hop = HopInfo(
            number: ttl,
            ip: ip,
            time: time > 0 ? time : null,
          );

          // Get GeoIP
          final geo = await GeoIPService.getBatchLocation([ip]);
          if (geo.containsKey(ip)) {
            hop.country = geo[ip]!['country'];
            hop.isp = geo[ip]!['isp'];
          }

          status.updateHops((hops) => hops.add(hop));

          // If it's a successful response (not TTL exceeded), we've reached the destination
          if (event.error == null) {
            break;
          }
        } else {
          // No response for this TTL
          status.updateHops(
            (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
          );
        }
      } catch (e) {
        // Timeout or other error
        status.updateHops(
          (hops) => hops.add(HopInfo(number: ttl, ip: null, time: null)),
        );
      }
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
