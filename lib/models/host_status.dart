import 'package:flutter/foundation.dart';

enum HostState { online, down, unknown, degraded, checking }

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

  Map<String, dynamic> toJson() => {
    'number': number,
    'ip': ip,
    'domain': domain,
    'time': time,
    'country': country,
    'isp': isp,
  };

  factory HopInfo.fromJson(Map<String, dynamic> json) => HopInfo(
    number: json['number'],
    ip: json['ip'],
    domain: json['domain'],
    time: json['time']?.toDouble(),
    country: json['country'],
    isp: json['isp'],
  );

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
  bool? _isDnsAvailable;
  bool? _isTlsAvailable;
  bool? _isHttpAvailable;
  int? _httpStatusCode;
  String? _diagnosis;

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
    bool? isDnsAvailable,
    bool? isTlsAvailable,
    bool? isHttpAvailable,
    int? httpStatusCode,
    String? diagnosis,
  }) : _state = state,
       _rtt = rtt,
       _errorMessage = errorMessage,
       _resolvedIp = resolvedIp,
       _resolvedCountry = resolvedCountry,
       _lastChecked = lastChecked,
       _hops = hops ?? [],
       _isTcpAvailable = isTcpAvailable,
       _isTracing = isTracing,
       _isDnsAvailable = isDnsAvailable,
       _isTlsAvailable = isTlsAvailable,
       _isHttpAvailable = isHttpAvailable,
       _httpStatusCode = httpStatusCode,
       _diagnosis = diagnosis;

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

  bool? get isDnsAvailable => _isDnsAvailable;
  set isDnsAvailable(bool? value) {
    if (_isDnsAvailable == value) return;
    _isDnsAvailable = value;
    notifyListeners();
  }

  bool? get isTlsAvailable => _isTlsAvailable;
  set isTlsAvailable(bool? value) {
    if (_isTlsAvailable == value) return;
    _isTlsAvailable = value;
    notifyListeners();
  }

  bool? get isHttpAvailable => _isHttpAvailable;
  set isHttpAvailable(bool? value) {
    if (_isHttpAvailable == value) return;
    _isHttpAvailable = value;
    notifyListeners();
  }

  int? get httpStatusCode => _httpStatusCode;
  set httpStatusCode(int? value) {
    if (_httpStatusCode == value) return;
    _httpStatusCode = value;
    notifyListeners();
  }

  String? get diagnosis => _diagnosis;
  set diagnosis(String? value) {
    if (_diagnosis == value) return;
    _diagnosis = value;
    notifyListeners();
  }

  void updateHops(void Function(List<HopInfo>) update) {
    update(_hops);
    notifyListeners();
  }

  bool get isOnline => _state == HostState.online;

  Map<String, dynamic> toJson() => {
    'category': category,
    'name': name,
    'host': host,
    'state': _state.index,
    'rtt': _rtt,
    'errorMessage': _errorMessage,
    'resolvedIp': _resolvedIp,
    'resolvedCountry': _resolvedCountry,
    'lastChecked': _lastChecked?.toIso8601String(),
    'hops': _hops.map((h) => h.toJson()).toList(),
    'isTcpAvailable': _isTcpAvailable,
    'isDnsAvailable': _isDnsAvailable,
    'isTlsAvailable': _isTlsAvailable,
    'isHttpAvailable': _isHttpAvailable,
    'httpStatusCode': _httpStatusCode,
    'diagnosis': _diagnosis,
  };

  factory HostStatus.fromJson(Map<String, dynamic> json) {
    final stateIndex = json['state'] ?? HostState.unknown.index;
    final state = stateIndex >= 0 && stateIndex < HostState.values.length
        ? HostState.values[stateIndex]
        : HostState.unknown;

    return HostStatus(
      category: json['category'],
      name: json['name'],
      host: json['host'],
      state: state,
      rtt: json['rtt']?.toDouble(),
      errorMessage: json['errorMessage'],
      resolvedIp: json['resolvedIp'],
      resolvedCountry: json['resolvedCountry'],
      lastChecked: json['lastChecked'] != null
          ? DateTime.parse(json['lastChecked'])
          : null,
      hops: (json['hops'] as List?)?.map((h) => HopInfo.fromJson(h)).toList(),
      isTcpAvailable: json['isTcpAvailable'] ?? false,
      isDnsAvailable: json['isDnsAvailable'],
      isTlsAvailable: json['isTlsAvailable'],
      isHttpAvailable: json['isHttpAvailable'],
      httpStatusCode: json['httpStatusCode'],
      diagnosis: json['diagnosis'],
    );
  }

  factory HostStatus.unknown(String category, String name, String host) {
    return HostStatus(category: category, name: name, host: host);
  }
}
