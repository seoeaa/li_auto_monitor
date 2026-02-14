import 'dart:convert';
import 'package:http/http.dart' as http;

class GeoIPService {
  static const String _apiEndpoint = 'http://ip-api.com/batch';

  static Future<Map<String, Map<String, String>>> getBatchLocation(
    List<String?> ips,
  ) async {
    final Map<String, Map<String, String>> results = {};
    final validIps = ips.where((ip) => ip != null && ip.isNotEmpty).toList();

    if (validIps.isEmpty) return results;

    try {
      final response = await http
          .post(Uri.parse(_apiEndpoint), body: jsonEncode(validIps))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (int i = 0; i < data.length; i++) {
          final item = data[i];
          final ip = validIps[i];
          if (item['status'] == 'success') {
            results[ip!] = {
              'country': item['country'] ?? '??',
              'isp': item['isp'] ?? 'Unknown ISP',
            };
          }
        }
      }
    } catch (e) {
      print('GeoIP Batch Error: $e');
    }
    return results;
  }
}
