import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/diagnostic_result.dart';
import '../utils/logger.dart';

class HistoryEntry {
  final String host;
  final DateTime timestamp;
  final DateTime observedUntil;
  final HostState state;
  final String? sessionId;

  HistoryEntry({
    required this.host,
    required this.timestamp,
    bool? isOnline,
    HostState? state,
    DateTime? observedUntil,
    this.sessionId,
  }) : state =
           state ??
           (isOnline == null
               ? HostState.unknown
               : isOnline
               ? HostState.online
               : HostState.down),
       observedUntil = observedUntil ?? timestamp;

  bool get isOnline => state == HostState.online;

  HistoryEntry until(DateTime end) => HistoryEntry(
    host: host,
    timestamp: timestamp,
    state: state,
    observedUntil: end,
    sessionId: sessionId,
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'timestamp': timestamp.toIso8601String(),
    'observedUntil': observedUntil.toIso8601String(),
    'state': state.name,
    'isOnline': isOnline,
    'sessionId': sessionId,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.parse(json['timestamp'] as String);
    final state = HostState.values
        .where((value) => value.name == json['state'])
        .firstOrNull;
    final end = json['observedUntil'] is String
        ? DateTime.parse(json['observedUntil'] as String)
        : timestamp;
    return HistoryEntry(
      host: json['host'] as String,
      timestamp: timestamp,
      state: state,
      isOnline: json['isOnline'] as bool?,
      // Legacy samples have no confirmed interval. Never invent one on migration.
      observedUntil: end.isBefore(timestamp) ? timestamp : end,
      sessionId: json['sessionId'] as String?,
    );
  }
}

class HistoryStatistics {
  final Duration online;
  final Duration degraded;
  final Duration down;
  final Duration period;
  const HistoryStatistics(this.online, this.degraded, this.down, this.period);
  Duration get observed => online + degraded + down;
  double get coveragePercent => period.inMilliseconds <= 0
      ? 0
      : (100 * observed.inMilliseconds / period.inMilliseconds)
            .clamp(0, 100)
            .toDouble();
  double? get uptimePercent => observed.inMilliseconds == 0
      ? null
      : 100 * (online + degraded).inMilliseconds / observed.inMilliseconds;
}

class HistoryService {
  static const String _fileName = 'monitor_history.v2.json';
  static const Duration _retention = Duration(days: 30);
  static const Duration _minimumSampleInterval = Duration(minutes: 5);
  static const Duration maxObservationGap = Duration(seconds: 90);
  static final List<HistoryEntry> _history = [];
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static bool _isInitialized = false;
  static bool _dirty = false;
  static bool _loadedBackup = false;
  static DateTime? _lastWrite;
  static Directory? _directory;
  static DateTime Function() _now = DateTime.now;
  static Future<void>? _initialization;
  static Future<void> _pending = Future.value();

  static Future<void> init() {
    if (_isInitialized) return Future.value();
    if (_initialization != null) return _initialization!;
    final future = _load();
    _initialization = future;
    // Retain the error for the caller, but allow a later retry.
    future.catchError((Object error) {
      _initialization = null;
      AppLogger.error('History initialization failed', error: error);
    });
    return future;
  }

  static Future<void> _load() async {
    final file = await _getFile();
    final backup = File('${file.path}.bak');
    final legacy = File('${file.parent.path}/monitor_history.json');
    List<HistoryEntry>? loaded;
    Object? failure;
    for (final source in [file, backup]) {
      if (!await source.exists()) continue;
      try {
        final decoded =
            jsonDecode(await source.readAsString()) as Map<String, dynamic>;
        if (decoded['version'] != 2) {
          throw const FormatException('Unsupported history version');
        }
        loaded = (decoded['entries'] as List)
            .map(
              (entry) => HistoryEntry.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ),
            )
            .toList();
        _loadedBackup = source.path == backup.path;
        break;
      } catch (error) {
        failure = error;
      }
    }
    if (loaded == null && failure != null) throw failure;
    if (loaded == null && await legacy.exists()) {
      final decoded = jsonDecode(await legacy.readAsString()) as List;
      loaded = decoded
          .map(
            (entry) =>
                HistoryEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    }
    _history
      ..clear()
      ..addAll(loaded ?? []);
    _cleanupOldData();
    _isInitialized = true;
    changes.value++;
  }

  static Future<void> _queue(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.catchError((Object error) {
      AppLogger.error('History operation failed', error: error);
    });
    return next;
  }

  // Compatibility methods intentionally create isolated observations; they do
  // not claim continuous monitoring without an explicit session identifier.
  static Future<void> saveEntry(String host, bool isOnline) =>
      saveSnapshot({host: isOnline});
  static Future<void> saveSnapshot(Map<String, bool> states) =>
      saveObservations([
        for (final entry in states.entries)
          HistoryEntry(
            host: entry.key,
            timestamp: _now(),
            isOnline: entry.value,
          ),
      ]);

  static Future<void> saveObservations(List<HistoryEntry> entries) => _queue(
    () async {
      await init();
      var forceWrite = false;
      for (final entry in entries) {
        if (entry.state == HostState.checking ||
            entry.state == HostState.unknown) {
          continue;
        }
        final lastIndex = _history.lastIndexWhere(
          (value) => value.host == entry.host,
        );
        final last = lastIndex < 0 ? null : _history[lastIndex];
        final gap = last == null
            ? null
            : entry.timestamp.difference(last.observedUntil);
        final continuous =
            last != null &&
            entry.sessionId != null &&
            last.sessionId == entry.sessionId &&
            gap! >= Duration.zero &&
            gap <= maxObservationGap;
        if (continuous) {
          // The preceding sampled state is carried only to the next confirmed
          // measurement, never to DateTime.now() or through a stopped session.
          _history[lastIndex] = last.until(entry.timestamp);
          if (last.state != entry.state) {
            _history.add(entry.until(entry.timestamp));
            forceWrite = true;
          }
        } else {
          _history.add(entry.until(entry.timestamp));
          forceWrite = true;
        }
        _dirty = true;
      }
      _cleanupOldData();
      if (_dirty &&
          (forceWrite ||
              _lastWrite == null ||
              _now().difference(_lastWrite!) >= _minimumSampleInterval)) {
        await _saveToFile();
      }
      changes.value++;
    },
  );

  static List<HistoryEntry> getHistory(String host) =>
      _history.where((entry) => entry.host == host).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  static List<HistoryEntry> segmentsFor(
    String host,
    DateTime startTime,
    DateTime endTime,
  ) {
    if (!endTime.isAfter(startTime)) return [];
    final segments = <HistoryEntry>[];
    var cursor = startTime;
    for (final entry in getHistory(host)) {
      final start = entry.timestamp.isAfter(cursor) ? entry.timestamp : cursor;
      final end = entry.observedUntil.isBefore(endTime)
          ? entry.observedUntil
          : endTime;
      if (!end.isAfter(start)) continue;
      if (entry.state == HostState.unknown ||
          entry.state == HostState.checking) {
        continue;
      }
      segments.add(
        HistoryEntry(
          host: entry.host,
          timestamp: start,
          observedUntil: end,
          state: entry.state,
          sessionId: entry.sessionId,
        ),
      );
      cursor = end;
    }
    return segments;
  }

  static HistoryStatistics statistics(
    String host,
    DateTime startTime,
    DateTime endTime,
  ) {
    var online = Duration.zero;
    var degraded = Duration.zero;
    var down = Duration.zero;
    for (final entry in segmentsFor(host, startTime, endTime)) {
      final duration = entry.observedUntil.difference(entry.timestamp);
      switch (entry.state) {
        case HostState.online:
          online += duration;
        case HostState.degraded:
          degraded += duration;
        case HostState.down:
          down += duration;
        case HostState.unknown || HostState.checking:
          break;
      }
    }
    return HistoryStatistics(
      online,
      degraded,
      down,
      endTime.isAfter(startTime)
          ? endTime.difference(startTime)
          : Duration.zero,
    );
  }

  static double? calculateUptime(
    String host,
    DateTime startTime,
    DateTime endTime,
  ) => statistics(host, startTime, endTime).uptimePercent;

  static void _cleanupOldData() {
    final cutoff = _now().subtract(_retention);
    _history.removeWhere((entry) => entry.observedUntil.isBefore(cutoff));
  }

  static Future<File> _getFile() async {
    final directory = _directory ?? await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/$_fileName');
  }

  static Future<void> _saveToFile() async {
    final file = await _getFile();
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(
      jsonEncode({
        'version': 2,
        'entries': _history.map((entry) => entry.toJson()).toList(),
      }),
      flush: true,
    );
    // Serialized writes plus temp/backup make interrupted replacement recoverable
    // on Windows as well as POSIX. Never rotate a corrupt primary over a good backup.
    if (_loadedBackup) {
      if (await file.exists()) await file.delete();
    } else if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    await temp.rename(file.path);
    _loadedBackup = false;
    _dirty = false;
    _lastWrite = _now();
  }

  static Future<void> flush() => _queue(() async {
    if (_isInitialized && _dirty) await _saveToFile();
  });

  static Future<void> clearHistory() => _queue(() async {
    await init();
    _history.clear();
    _dirty = true;
    await _saveToFile();
    final file = await _getFile();
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    changes.value++;
  });

  @visibleForTesting
  static Future<void> resetForTesting({
    Directory? directory,
    DateTime Function()? now,
  }) async {
    await _pending;
    _directory = directory;
    _now = now ?? DateTime.now;
    _history.clear();
    _isInitialized = false;
    _initialization = null;
    _dirty = false;
    _loadedBackup = false;
    _lastWrite = null;
    _pending = Future.value();
    changes.value++;
  }
}
