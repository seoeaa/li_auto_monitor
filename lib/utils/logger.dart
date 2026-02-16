import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';

class AppLogger {
  static final _logger = Logger('LiAutoMonitor');

  static void init() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (kDebugMode) {
        print(
          '${record.level.name}: ${record.time}: ${record.message}${record.error != null ? '\nError: ${record.error}' : ''}',
        );
      }
    });
  }

  static void debug(String message) => _logger.fine(message);
  static void info(String message) => _logger.info(message);
  static void warning(String message) => _logger.warning(message);
  static void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.severe(message, error, stackTrace);
}
