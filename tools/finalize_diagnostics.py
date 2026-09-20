from pathlib import Path
root = Path(__file__).resolve().parents[1]

p = root / 'lib/services/network_probe.dart'
s = p.read_text()
old = "    final client = HttpClient(context: securityContext)\n      ..findProxy = (_) => 'DIRECT'..autoUncompress = false;"
new = "    final client = HttpClient(context: securityContext);\n    client.findProxy = (_) => 'DIRECT';\n    client.autoUncompress = false;"
if old in s:
    s = s.replace(old, new)
elif new not in s:
    raise RuntimeError('Unexpected HttpClient configuration')
if 'SecureSocket.secure(' not in s:
    s = s.replace('    // HttpClient performs TLS on this exact socket. The original URI supplies\n    // SNI, certificate hostname validation and Host. No second DNS lookup occurs.',
                  '    // A custom connectionFactory must provide its own TLS socket.\n    // Pin the TCP address, then verify TLS using the original hostname/SNI.')
    s = s.replace('final connected = connectionTask.socket.then((value) {', 'final connected = connectionTask.socket.then<Socket>((value) async {')
    old = '        stageWatch.reset();\n        return value;'
    new = '''        stageWatch.reset();
        final secureSocket = await SecureSocket.secure(
          value,
          host: host,
          context: securityContext,
          supportedProtocols: const ['http/1.1'],
        );
        if (closed) {
          secureSocket.destroy();
          throw const CheckCancelled();
        }
        socket = secureSocket;
        return secureSocket;'''
    if old not in s:
        raise RuntimeError('Missing TCP-to-TLS transition')
    s = s.replace(old, new)
p.write_text(s)

p = root / 'lib/services/monitor_service.dart'
s = p.read_text()
old = "      await HistoryService.saveObservations(observations);\n      historyError = null;\n    } catch (error) {"
new = "      await cancellation.wait(\n        HistoryService.saveObservations(observations),\n        timeout: const Duration(seconds: 5),\n      );\n      historyError = null;\n    } on CheckCancelled {\n      return;\n    } on TimeoutException {\n      historyError = 'Запись истории ещё не завершена.';\n    } catch (error) {"
if old in s:
    s = s.replace(old, new)
p.write_text(s)

p = root / 'lib/services/geoip_service.dart'
s = p.read_text()
s = s.replace('        address.isMulticast)\n      return false;', '        address.isMulticast) {\n      return false;\n    }')
s = s.replace("              if (data is! Map<String, dynamic> || data['error'] == true)\n                return;", "              if (data is! Map<String, dynamic> || data['error'] == true) {\n                return;\n              }")
p.write_text(s)

p = root / 'test/network_probe_test.dart'
s = p.read_text()
s = s.replace("          if (code == 301)\n            request.response.headers.set(\n              HttpHeaders.locationHeader,\n              'https://never-request.invalid/',\n            );", "          if (code == 301) {\n            request.response.headers.set(\n              HttpHeaders.locationHeader,\n              'https://never-request.invalid/',\n            );\n          }")
p.write_text(s)
