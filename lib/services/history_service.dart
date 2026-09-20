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
  static const Duration _retention = Duration(days: 30);
  static const Duration _minimumSampleInterval = Duration(minutes: 5);
  static final List<HistoryEntry> _history = [];
  static bool _isInitialized = false;

  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          _history.clear();
          _history.addAll(jsonList.map((j) => HistoryEntry.fromJson(j)));
        }
      }
      _cleanupOldData();
      _isInitialized = true;
    } catch (e) {
      AppLogger.error('HistoryService init error', error: e);
    }
  }

  static Future<void> saveEntry(String host, bool isOnline) async {
    await saveSnapshot({host: isOnline});
  }

  static Future<void> saveSnapshot(Map<String, bool> states) async {
    await init();
    final now = DateTime.now();
    bool changed = false;

    for (final entry in states.entries) {
      final last = _lastForHost(entry.key);
      final shouldStore =
          last == null ||
          last.isOnline != entry.value ||
          now.difference(last.timestamp) >= _minimumSampleInterval;

      if (!shouldStore) continue;

      _history.add(
        HistoryEntry(
          host: entry.key,
          timestamp: now,
          isOnline: entry.value,
        ),
      );
      changed = true;
    }

    if (!changed) return;

    _cleanupOldData();
    await _saveToFile();
  }

  static List<HistoryEntry> getHistory(String host) {
    return _history.where((e) => e.host == host).toList();
  }

  static double? calculateUptime(
    String host,
    DateTime startTime,
    DateTime endTime,
  ) {
    final history = getHistory(host)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (history.isEmpty || !endTime.isAfter(startTime)) {
      return null;
    }

    HistoryEntry? stateAtStart;
    final entriesInRange = <HistoryEntry>[];

    for (final entry in history) {
      if (!entry.timestamp.isAfter(startTime)) {
        stateAtStart = entry;
      } else if (entry.timestamp.isBefore(endTime)) {
        entriesInRange.add(entry);
      }
    }

    if (stateAtStart == null && entriesInRange.isEmpty) {
      return null;
    }

    DateTime cursor;
    bool currentState;
    Duration knownDuration = Duration.zero;
    Duration onlineDuration = Duration.zero;

    if (stateAtStart != null) {
      cursor = startTime;
      currentState = stateAtStart.isOnline;
    } else {
      cursor = entriesInRange.first.timestamp;
      currentState = entriesInRange.first.isOnline;
      entriesInRange.removeAt(0);
    }

    for (final entry in entriesInRange) {
      if (!entry.timestamp.isAfter(cursor)) continue;
      final segment = entry.timestamp.difference(cursor);
      knownDuration += segment;
      if (currentState) onlineDuration += segment;
      cursor = entry.timestamp;
      currentState = entry.isOnline;
    }

    if (endTime.isAfter(cursor)) {
      final segment = endTime.difference(cursor);
      knownDuration += segment;
      if (currentState) onlineDuration += segment;
    }

    if (knownDuration.inMilliseconds <= 0) {
      return currentState ? 100.0 : 0.0;
    }

    return onlineDuration.inMilliseconds /
        knownDuration.inMilliseconds *
        100.0;
  }

  static HistoryEntry? _lastForHost(String host) {
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i].host == host) return _history[i];
    }
    return null;
  }

  static void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(_retention);
    _history.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }

  static Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  static Future<void> _saveToFile() async {
    try {
      final file = await _getFile();
      final content = jsonEncode(_history.map((e) => e.toJson()).toList());
      await file.writeAsString(content, flush: true);
    } catch (e) {
      AppLogger.error('HistoryService save error', error: e);
    }
  }

  static void clearHistory() {
    _history.clear();
    _saveToFile();
  }
}
