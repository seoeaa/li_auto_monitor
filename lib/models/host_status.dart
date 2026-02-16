import 'package:flutter/foundation.dart';

enum HostState { online, down, unknown }

class HopInfo {
  final int number;
  final String? ip;
  final String? domain;
  final double? time;
  String? country;
  String? isp;

  HopInfo({
    required this.number,
    this.ip,
    this.domain,
    this.time,
    this.country,
    this.isp,
  });

  bool get isSuccessful => ip != null;

  @override
  String toString() => '$number: $ip ($country) - ${time}ms';
}

class HostStatus extends ChangeNotifier {
  final String category;
  final String name;
  final String host;
  HostState _state;
  double? _rtt;
  String? _errorMessage;
  String? _resolvedIp;
  String? _resolvedCountry;
  DateTime? _lastChecked;
  List<HopInfo> _hops;
  bool _isTcpAvailable;
  bool _isTracing;

  HostStatus({
    required this.category,
    required this.name,
    required this.host,
    HostState state = HostState.unknown,
    double? rtt,
    String? errorMessage,
    String? resolvedIp,
    String? resolvedCountry,
    DateTime? lastChecked,
    List<HopInfo>? hops,
    bool isTcpAvailable = false,
    bool isTracing = false,
  }) : _state = state,
       _rtt = rtt,
       _errorMessage = errorMessage,
       _resolvedIp = resolvedIp,
       _resolvedCountry = resolvedCountry,
       _lastChecked = lastChecked,
       _hops = hops ?? [],
       _isTcpAvailable = isTcpAvailable,
       _isTracing = isTracing;

  HostState get state => _state;
  set state(HostState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  double? get rtt => _rtt;
  set rtt(double? value) {
    if (_rtt == value) return;
    _rtt = value;
    notifyListeners();
  }

  String? get errorMessage => _errorMessage;
  set errorMessage(String? value) {
    if (_errorMessage == value) return;
    _errorMessage = value;
    notifyListeners();
  }

  String? get resolvedIp => _resolvedIp;
  set resolvedIp(String? value) {
    if (_resolvedIp == value) return;
    _resolvedIp = value;
    notifyListeners();
  }

  String? get resolvedCountry => _resolvedCountry;
  set resolvedCountry(String? value) {
    if (_resolvedCountry == value) return;
    _resolvedCountry = value;
    notifyListeners();
  }

  DateTime? get lastChecked => _lastChecked;
  set lastChecked(DateTime? value) {
    if (_lastChecked == value) return;
    _lastChecked = value;
    notifyListeners();
  }

  List<HopInfo> get hops => _hops;
  set hops(List<HopInfo> value) {
    _hops = value;
    notifyListeners();
  }

  bool get isTcpAvailable => _isTcpAvailable;
  set isTcpAvailable(bool value) {
    if (_isTcpAvailable == value) return;
    _isTcpAvailable = value;
    notifyListeners();
  }

  bool get isTracing => _isTracing;
  set isTracing(bool value) {
    if (_isTracing == value) return;
    _isTracing = value;
    notifyListeners();
  }

  void updateHops(void Function(List<HopInfo>) update) {
    update(_hops);
    notifyListeners();
  }

  factory HostStatus.unknown(String category, String name, String host) {
    return HostStatus(category: category, name: name, host: host);
  }
}
