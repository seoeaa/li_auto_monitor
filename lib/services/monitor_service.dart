import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_ping/dart_ping.dart';
import '../models/host_status.dart';

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
    _timer = Timer.periodic(interval, (_) => _checkAllHosts());
    _checkAllHosts(); // Initial check
    notifyListeners();
  }

  void stopMonitoring() {
    _timer?.cancel();
    _isMonitoring = false;
    notifyListeners();
  }

  Future<void> _checkAllHosts() async {
    for (var hostStatus in _hosts) {
      _pingHost(hostStatus);
    }
  }

  void _pingHost(HostStatus hostStatus) {
    final ping = Ping(hostStatus.host, count: 1);

    ping.stream.listen((event) {
      if (event.response != null) {
        final response = event.response!;
        if (response.time != null) {
          hostStatus.state = HostState.online;
          hostStatus.rtt = response.time!.inMilliseconds.toDouble();
        } else {
          hostStatus.state = HostState.down;
          hostStatus.rtt = null;
        }
      } else if (event.error != null) {
        hostStatus.state = HostState.down;
        hostStatus.errorMessage = event.error.toString();
        hostStatus.rtt = null;
      }
      hostStatus.lastChecked = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
