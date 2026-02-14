enum HostState { online, down, unknown }

class HostStatus {
  final String category;
  final String name;
  final String host;
  HostState state;
  double? rtt;
  String? errorMessage;
  DateTime? lastChecked;

  HostStatus({
    required this.category,
    required this.name,
    required this.host,
    this.state = HostState.unknown,
    this.rtt,
    this.errorMessage,
    this.lastChecked,
  });

  factory HostStatus.unknown(String category, String name, String host) {
    return HostStatus(category: category, name: name, host: host);
  }
}
