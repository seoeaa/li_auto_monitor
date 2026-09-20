import 'dart:convert';
import 'package:http/http.dart' as http;

import '../utils/logger.dart';

class GeoIPService {
  static const String _apiHost = 'ipapi.co';

  static final Map<String, Map<String, String>> _cache = {};

  static Future<Map<String, Map<String, String>>> getBatchLocation(
    List<String?> ips,
  ) async {
    final Map<String, Map<String, String>> results = {};

    final uniqueIps = ips
        .where((ip) => ip != null && ip.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    if (uniqueIps.isEmpty) return results;

    final List<String> ipsToFetch = [];

    for (final ip in uniqueIps) {
      if (_cache.containsKey(ip)) {
        results[ip] = _cache[ip]!;
      } else {
        ipsToFetch.add(ip);
      }
    }

    if (ipsToFetch.isEmpty) return results;

    const int batchSize = 4;
    for (int i = 0; i < ipsToFetch.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, ipsToFetch.length).toInt();
      final batch = ipsToFetch.sublist(i, end);

      final fetched = await Future.wait(
        batch.map((ip) async => (ip: ip, data: await _fetchLocation(ip))),
      );

      for (final item in fetched) {
        if (item.data == null) continue;
        results[item.ip] = item.data!;
        _cache[item.ip] = item.data!;
      }
    }

    return results;
  }

  static Future<Map<String, String>?> _fetchLocation(String ip) async {
    try {
      AppLogger.debug('Fetching GeoIP for: $ip');

      final response = await http
          .get(
            Uri.https(_apiHost, '/$ip/json/'),
            headers: {'User-Agent': 'LiAutoMonitor/1.1'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        AppLogger.warning('GeoIP HTTP ${response.statusCode} for $ip');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['error'] == true) {
        return null;
      }

      final geoData = <String, String>{
        'country':
            (data['country_name'] as String?) ??
            (data['country'] as String?) ??
            '??',
        'isp':
            (data['org'] as String?) ??
            (data['asn'] as String?) ??
            'Unknown ISP',
      };

      AppLogger.debug('GeoIP Response for $ip: $geoData');
      return geoData;
    } catch (e) {
      AppLogger.error('GeoIP Error for $ip', error: e);
      return null;
    }
  }
}
