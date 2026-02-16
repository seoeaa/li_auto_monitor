import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/logger.dart';

class GeoIPService {
  static const String _apiEndpoint = 'http://ip-api.com/batch';

  // In-memory cache for IP metadata
  static final Map<String, Map<String, String>> _cache = {};

  static Future<Map<String, Map<String, String>>> getBatchLocation(
    List<String?> ips,
  ) async {
    final Map<String, Map<String, String>> results = {};

    // Filter out null/empty and deduplicate
    final uniqueIps = ips
        .where((ip) => ip != null && ip.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    if (uniqueIps.isEmpty) return results;

    final List<String> ipsToFetch = [];

    // Check cache first
    for (final ip in uniqueIps) {
      if (_cache.containsKey(ip)) {
        results[ip] = _cache[ip]!;
      } else {
        ipsToFetch.add(ip);
      }
    }

    if (ipsToFetch.isEmpty) return results;

    try {
      // ip-api.com supports up to 100 IPs per batch.
      // For simplicity, we assume we don't exceed this in one traceroute (usually max 30 hops).
      // If needed, we could chunk ipsToFetch here.

      final response = await http
          .post(Uri.parse(_apiEndpoint), body: jsonEncode(ipsToFetch))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (int i = 0; i < data.length; i++) {
          final item = data[i];
          final ip = ipsToFetch[i];
          if (item['status'] == 'success') {
            final geoData = <String, String>{
              'country': (item['country'] as String?) ?? '??',
              'isp': (item['isp'] as String?) ?? 'Unknown ISP',
            };
            results[ip] = geoData;
            _cache[ip] = geoData; // Update cache
          }
        }
      }
    } catch (e) {
      AppLogger.error('GeoIP Batch Error', error: e);
    }
    return results;
  }
}
