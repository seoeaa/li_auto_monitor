import 'package:html/parser.dart' show parse;
import '../models/host_status.dart';

class ReportParser {
  static List<HostStatus> parseReport(String htmlContent) {
    final document = parse(htmlContent);
    final List<HostStatus> hosts = [];

    // The host information is in a table within the summary section (ИТОГОВЫЙ ОТЧЕТ)
    // Looking for the table that contains "ИТОГОВЫЙ ОТЧЕТ" or similar markers
    // Based on the HTML structure provided, the table is after line 257

    // Fallback: look for spans with r3 (blue color in the report for borders)
    // and extract host info from the text between them.
    // However, the report is essentially a pre-formatted text block with spans for colors.

    final preContent = document.querySelector('pre');
    if (preContent == null) return [];

    final text = preContent.text;
    final lines = text.split('\n');

    bool inSummary = false;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains("ИТОГОВЫЙ ОТЧЕТ ДОСТУПНОСТИ СЕРВИСОВ")) {
        inSummary = true;
        i += 4; // Skip headers
        continue;
      }

      if (inSummary) {
        if (lines[i].contains("╰") ||
            lines[i].contains("РЕЗУЛЬТАТЫ СОХРАНЕНЫ")) {
          break;
        }

        // Example line: │ OTA        │ OTA MA JWT                │ api-hmi-cnnx01.chehejia.com         │    ONLINE    │       4 ms │ OK        │
        final parts = lines[i].split('│').map((e) => e.trim()).toList();
        if (parts.length >= 4) {
          final category = parts[1].isNotEmpty
              ? parts[1]
              : (hosts.isNotEmpty ? hosts.last.category : "Unknown");
          final name = parts[2];
          final host = parts[3];

          if (name.isNotEmpty && host.isNotEmpty) {
            hosts.add(HostStatus.unknown(category, name, host));
          }
        }
      }
    }

    return hosts;
  }
}
