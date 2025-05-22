import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// LogService is a centralized logging utility for the entire application.
/// It replaces all direct print and debugPrint calls with structured logging.
class LogService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, // Don't show method count
      errorMethodCount: 5, // Show more methods for errors
      lineLength: 80, // Shorter line length
      colors: false, // Disable colors to prevent ANSI codes
      printEmojis: false, // Disable emojis
      noBoxingByDefault: true, // Disable boxes around log messages
    ),
    level: kReleaseMode ? Level.warning : Level.verbose,
  );

  // For persistent logging to file in production
  static final Logger _fileLogger = Logger(
    printer: SimplePrinter(printTime: true, colors: false),
    level: Level.warning,
  );

  /// Log debug message - only for development
  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message - generally useful information
  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message - potentially harmful situations
  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);

    if (kReleaseMode) {
      _fileLogger.w(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log error message - runtime errors that shouldn't happen
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);

    if (kReleaseMode) {
      _fileLogger.e(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log critical error - severe errors that cause app to crash
  static void wtf(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);

    if (kReleaseMode) {
      _fileLogger.f(message, error: error, stackTrace: stackTrace);
    }
  }
}
