import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';
import 'network_probe.dart';

class GeoIPService {
  static const String _apiHost = 'ipapi.co';
  static final Map<String, Map<String, String>> _cache = {};

  static bool isPublicAddress(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast) {
      return false;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return !(bytes[0] == 0 ||
          bytes[0] == 10 ||
          bytes[0] >= 224 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127));
    }
    // IPv4-mapped IPv6 must obey the same private-address exclusions.
    if (bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return isPublicAddress(bytes.sublist(12).join('.'));
    }
    return (bytes[0] & 0xfe) != 0xfc && bytes.any((byte) => byte != 0);
  }

  static Future<Map<String, Map<String, String>>> getBatchLocation(
    List<String?> ips, {
    CheckCancellation? cancellation,
  }) async {
    final results = <String, Map<String, String>>{};
    final uniqueIps = ips.whereType<String>().where(isPublicAddress).toSet();
    final ipsToFetch = <String>[];
    for (final ip in uniqueIps) {
      if (_cache.containsKey(ip)) {
        results[ip] = _cache[ip]!;
      } else {
        ipsToFetch.add(ip);
      }
    }
    if (ipsToFetch.isEmpty || cancellation?.isCancelled == true) return results;
    final client = http.Client();
    final token = CheckCancellation();
    final removeParent = cancellation?.onCancel(token.cancel);
    final removeClose = token.onCancel(client.close);
    final deadline = Timer(const Duration(seconds: 5), token.cancel);
    try {
      for (
        var index = 0;
        index < ipsToFetch.length && !token.isCancelled;
        index += 4
      ) {
        final end = (index + 4).clamp(0, ipsToFetch.length).toInt();
        await Future.wait(
          ipsToFetch.sublist(index, end).map((ip) async {
            try {
              final response = await token.wait(
                client.get(
                  Uri.https(_apiHost, '/$ip/json/'),
                  headers: {'User-Agent': 'LiAutoMonitor/1.1'},
                ),
                timeout: const Duration(seconds: 2),
              );
              if (token.isCancelled || response.statusCode != 200) return;
              final data = jsonDecode(response.body);
              if (data is! Map<String, dynamic> || data['error'] == true) {
                return;
              }
              final geoData = <String, String>{
                'country':
                    data['country_name'] as String? ??
                    data['country'] as String? ??
                    'Не определено',
                'isp':
                    data['org'] as String? ??
                    data['asn'] as String? ??
                    'Не определено',
              };
              results[ip] = geoData;
              _cache[ip] = geoData;
            } catch (error) {
              AppLogger.debug(
                'Optional GeoIP request failed: ${error.runtimeType}',
              );
            }
          }),
        );
      }
    } finally {
      deadline.cancel();
      removeParent?.call();
      removeClose();
      client.close();
    }
    return results;
  }
}
