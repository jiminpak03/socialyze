import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../analysis/session_analyzer.dart';

// ============================================================================
// Session History Model
// ============================================================================

class SessionHistoryEntry {
  final int id;
  final String protocol;
  final DateTime startedAt;
  final DateTime stoppedAt;
  final Duration duration;
  final int mouseCount;
  final Map<String, Map<String, int>> mouseDwellTimes;

  SessionHistoryEntry({
    required this.id,
    required this.protocol,
    required this.startedAt,
    required this.stoppedAt,
    required this.duration,
    required this.mouseCount,
    required this.mouseDwellTimes,
  });

  /// Convert to JSON map for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'protocol': protocol,
    'startedAt': startedAt.toIso8601String(),
    'stoppedAt': stoppedAt.toIso8601String(),
    'duration': duration.inMilliseconds,
    'mouseCount': mouseCount,
    'mouseDwellTimes': mouseDwellTimes,
  };

  /// Create from JSON map
  factory SessionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SessionHistoryEntry(
      id: json['id'] as int,
      protocol: json['protocol'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      stoppedAt: DateTime.parse(json['stoppedAt'] as String),
      duration: Duration(milliseconds: json['duration'] as int),
      mouseCount: json['mouseCount'] as int,
      mouseDwellTimes: Map<String, Map<String, int>>.from(
        (json['mouseDwellTimes'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            Map<String, int>.from(value as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Session History Storage (File-based JSON)
// ============================================================================

class SessionHistoryDatabase {
  static const String _fileName = 'session_history.json';
  static File? _historyFile;
  static List<SessionHistoryEntry> _cache = [];
  static int _nextId = 1;

  /// Initialize the database file
  static Future<File> _getHistoryFile() async {
    if (_historyFile != null) return _historyFile!;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    _historyFile = File(path.join(documentsDirectory.path, _fileName));

    // Initialize file if it doesn't exist
    if (!_historyFile!.existsSync()) {
      await _historyFile!.writeAsString(jsonEncode({'sessions': [], 'nextId': 1}));
    }

    // Load existing data
    await _loadFromFile();
    return _historyFile!;
  }

  /// Load sessions from file
  static Future<void> _loadFromFile() async {
    final file = _historyFile;
    if (file == null || !file.existsSync()) return;

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _nextId = data['nextId'] as int? ?? 1;

      final sessions = (data['sessions'] as List<dynamic>? ?? [])
          .map((e) => SessionHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      _cache = sessions;
    } catch (e) {
      _cache = [];
    }
  }

  /// Save sessions to file
  static Future<void> _saveToFile() async {
    final file = await _getHistoryFile();
    final data = {
      'sessions': _cache.map((e) => e.toJson()).toList(),
      'nextId': _nextId,
    };
    await file.writeAsString(jsonEncode(data));
  }

  /// Add a new session record
  static Future<int> addSession({
    required String protocol,
    required DateTime startedAt,
    required DateTime stoppedAt,
    required SessionSummary summary,
  }) async {
    await _getHistoryFile();

    // Convert mouse summaries to dwell times
    final mouseDwellTimes = <String, Map<String, int>>{};
    for (final entry in summary.mouseSummaries.entries) {
      mouseDwellTimes[entry.key] = {
        'empty': entry.value.dwellTime(Chamber.empty).inMilliseconds,
        'middle': entry.value.dwellTime(Chamber.middle).inMilliseconds,
        'stranger': entry.value.dwellTime(Chamber.stranger).inMilliseconds,
        'switches': entry.value.switchCount,
      };
    }

    final entry = SessionHistoryEntry(
      id: _nextId++,
      protocol: protocol,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      duration: summary.duration,
      mouseCount: summary.mouseSummaries.length,
      mouseDwellTimes: mouseDwellTimes,
    );

    _cache.insert(0, entry);
    await _saveToFile();
    return entry.id;
  }

  /// Get all session records
  static Future<List<SessionHistoryEntry>> getAllSessions() async {
    await _getHistoryFile();
    return List.from(_cache);
  }

  /// Get a specific session record
  static Future<SessionHistoryEntry?> getSession(int id) async {
    await _getHistoryFile();
    try {
      return _cache.firstWhere((entry) => entry.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Delete a session record
  static Future<bool> deleteSession(int id) async {
    await _getHistoryFile();
    final length = _cache.length;
    _cache.removeWhere((entry) => entry.id == id);
    
    if (_cache.length < length) {
      await _saveToFile();
      return true;
    }
    return false;
  }

  /// Delete all session records
  static Future<void> deleteAllSessions() async {
    await _getHistoryFile();
    _cache.clear();
    _nextId = 1;
    await _saveToFile();
  }
}

// ============================================================================
// Riverpod Providers for Database Access
// ============================================================================

final sessionHistoryProvider = FutureProvider<List<SessionHistoryEntry>>((ref) async {
  return SessionHistoryDatabase.getAllSessions();
});

