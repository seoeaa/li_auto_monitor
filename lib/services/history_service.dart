import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

class HistoryEntry {
  final String host;
  final DateTime timestamp;
  final bool isOnline;

  HistoryEntry({
    required this.host,
    required this.timestamp,
    required this.isOnline,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'timestamp': timestamp.toIso8601String(),
    'isOnline': isOnline,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    host: json['host'],
    timestamp: DateTime.parse(json['timestamp']),
    isOnline: json['isOnline'],
  );
}

class HistoryService {
  static const String _fileName = 'monitor_history.json';
  static final List<HistoryEntry> _history = [];
  static bool _isInitialized = false;

  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _history.clear();
        _history.addAll(jsonList.map((j) => HistoryEntry.fromJson(j)));

        // Cleanup old data (older than 30 days)
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        _history.removeWhere((e) => e.timestamp.isBefore(thirtyDaysAgo));
      }
      _isInitialized = true;
    } catch (e) {
      AppLogger.error('HistoryService init error', error: e);
    }
  }

  static Future<void> saveEntry(String host, bool isOnline) async {
    await init();
    final entry = HistoryEntry(
      host: host,
      timestamp: DateTime.now(),
      isOnline: isOnline,
    );
    _history.add(entry);

    // Limit history size per host to avoid massive files?
    // Or just rely on the 30-day cleanup in init.

    await _saveToFile();
  }

  static List<HistoryEntry> getHistory(String host) {
    return _history.where((e) => e.host == host).toList();
  }

  static Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  static Future<void> _saveToFile() async {
    try {
      final file = await _getFile();
      final content = jsonEncode(_history.map((e) => e.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      AppLogger.error('HistoryService save error', error: e);
    }
  }

  static void clearHistory() {
    _history.clear();
    _saveToFile();
  }
}
