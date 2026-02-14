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

class HostStatus {
  final String category;
  final String name;
  final String host;
  HostState state;
  double? rtt;
  String? errorMessage;
  String? resolvedIp;
  String? resolvedCountry;
  DateTime? lastChecked;
  List<HopInfo> hops;
  bool isTcpAvailable;
  bool isTracing;

  HostStatus({
    required this.category,
    required this.name,
    required this.host,
    this.state = HostState.unknown,
    this.rtt,
    this.errorMessage,
    this.resolvedIp,
    this.resolvedCountry,
    this.lastChecked,
    List<HopInfo>? hops,
    this.isTcpAvailable = false,
    this.isTracing = false,
  }) : hops = hops ?? [];

  factory HostStatus.unknown(String category, String name, String host) {
    return HostStatus(category: category, name: name, host: host);
  }
}
