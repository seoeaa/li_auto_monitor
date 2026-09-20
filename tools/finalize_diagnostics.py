from pathlib import Path
root = Path(__file__).resolve().parents[1]

p = root / 'lib/services/geoip_service.dart'
s = p.read_text().replace('(index + 4).clamp(0, ipsToFetch.length);', '(index + 4).clamp(0, ipsToFetch.length).toInt();')
if 'IPv4-mapped' not in s:
    s = s.replace('    return (bytes[0] & 0xfe)', "    // IPv4-mapped IPv6 must obey the same private-address exclusions.\n    if (bytes.take(10).every((byte) => byte == 0) && bytes[10] == 255 && bytes[11] == 255) {\n      return isPublicAddress(bytes.sublist(12).join('.'));\n    }\n    return (bytes[0] & 0xfe)")
p.write_text(s)

p = root / 'lib/services/monitor_service.dart'
s = p.read_text()
if '_enrichLocations(' not in s:
    s = s.replace("import 'network_probe.dart';", "import 'network_probe.dart';\nimport 'geoip_service.dart';")
    marker = '  Future<void> traceHost(HostStatus status) async {'
    pos = s.index(marker)
    prefix = s[:pos]
    last = prefix.rfind('  }')
    prefix = prefix[:last] + '    if (!_disposed && !cancellation.isCancelled) {\n      await _enrichLocations(cancellation);\n    }\n' + prefix[last:]
    helper = r'''  Future<void> _enrichLocations(CheckCancellation cancellation, {HostStatus? tracedHost}) async {
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

'''
    s = prefix + helper + s[pos:]
    start = s.index(marker)
    end = s.index('    } on CheckCancelled {', start)
    s = s[:end] + '      if (!_disposed && !cancellation.isCancelled) {\n        await _enrichLocations(cancellation, tracedHost: status);\n      }\n' + s[end:]
p.write_text(s)
