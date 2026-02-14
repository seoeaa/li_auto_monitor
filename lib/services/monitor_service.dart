import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';
import 'geoip_service.dart';

class MonitorService extends ChangeNotifier {
  List<HostStatus> _hosts = [
    HostStatus.unknown('OTA', 'OTA MA JWT', 'api-hmi-cnnx01.chehejia.com'),
    HostStatus.unknown('OTA', 'OTA Production', 'api-hmi.chehejia.com'),
    HostStatus.unknown('OTA', 'OTA Test', 'api-hmi-test.chehejia.com'),
    HostStatus.unknown(
      'OTA',
      'OTA OnTest',
      'iot-api-hmi-ontest-b.chehejia.com',
    ),
    HostStatus.unknown('APP', 'App Diagnosis', 'api-app.lixiang.com'),
    HostStatus.unknown('APP', 'Li Auto Auth', 'id.lixiang.com'),
    HostStatus.unknown('APP', 'Li API Base', 'li.auto'),
  ];
  bool _isMonitoring = false;
  Timer? _timer;

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
        status.hops = [
          HopInfo(number: 1, ip: event.response!.ip, time: status.rtt),
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
    notifyListeners();
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
          final ip = event.response!.ip!;
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

          status.hops.add(hop);
          notifyListeners();

          // If it's a successful response (not TTL exceeded), we've reached the destination
          if (event.error == null) {
            break;
          }
        } else {
          // No response for this TTL
          status.hops.add(HopInfo(number: ttl, ip: null, time: null));
          notifyListeners();
        }
      } catch (e) {
        // Timeout or other error
        status.hops.add(HopInfo(number: ttl, ip: null, time: null));
        notifyListeners();
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
