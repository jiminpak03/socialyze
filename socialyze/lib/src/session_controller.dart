import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/session_analyzer.dart';
import 'session_database.dart';

// ============================================================================
// Protocol Extension: Readable Labels
// ============================================================================

extension on Protocol {
  String get label {
    switch (this) {
      case Protocol.socialInteraction:
        return 'Social Interaction';
      case Protocol.socialNovelty:
        return 'Social Novelty';
    }
  }
}

// ============================================================================
// Default Key Bindings
// ============================================================================

/// Generates default numpad key bindings for three mice.
/// Maps: Mouse A (7/4/1), Mouse B (8/5/2), Mouse C (9/6/3)
Map<String, Map<Chamber, LogicalKeyboardKey>> _generateDefaultKeyBindings(
  List<String> mouseIds,
) {
  const keyGrid = <List<LogicalKeyboardKey>>[
    [
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad1,
    ],
    [
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad2,
    ],
    [
      LogicalKeyboardKey.numpad9,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad3,
    ],
  ];

  const chamberOrder = [Chamber.empty, Chamber.middle, Chamber.stranger];

  final map = <String, Map<Chamber, LogicalKeyboardKey>>{};
  for (var mouseIndex = 0; mouseIndex < mouseIds.length; mouseIndex++) {
    final chambers = <Chamber, LogicalKeyboardKey>{};
    for (var chamberIndex = 0;
        chamberIndex < chamberOrder.length;
        chamberIndex++) {
      chambers[chamberOrder[chamberIndex]] = keyGrid[mouseIndex][chamberIndex];
    }
    map[mouseIds[mouseIndex]] = chambers;
  }
  return map;
}

// ============================================================================
// Session Event: Immutable Recording Event Snapshot
// ============================================================================

/// Represents a single event during a recording session.
/// Captures mouse ID, chamber location, and timestamp.
class SessionEvent {
  SessionEvent({
    required this.mouseId,
    required this.chamber,
    required this.timestamp,
  });

  final String mouseId;
  final Chamber chamber;
  final DateTime timestamp;
}

// ============================================================================
// Protocol Enum: Supported Study Types
// ============================================================================

/// Enumeration of supported protocols for social interaction studies.
enum Protocol {
  socialInteraction,
  socialNovelty,
}

// ============================================================================
// Session State: Immutable Session Snapshot
// ============================================================================

/// Immutable snapshot of the session recording state.
/// Holds all data about the current or completed session including
/// events, video path, and computed analytics summary.
class SessionState {
  SessionState({
    required this.protocol,
    this.isRecording = false,
    this.startedAt,
    this.stoppedAt,
    List<SessionEvent>? events,
    this.videoPath,
    this.summary,
    Map<String, Map<Chamber, LogicalKeyboardKey>>? keyMap,
  })  : events =
            events == null ? const [] : List<SessionEvent>.unmodifiable(events),
        keyMap = keyMap ?? _generateDefaultKeyBindings(['Mouse A', 'Mouse B', 'Mouse C']);

  final Protocol protocol;
  final bool isRecording;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final List<SessionEvent> events;
  final String? videoPath;
  final SessionSummary? summary;
  final Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap;

  SessionState copyWith({
    Protocol? protocol,
    bool? isRecording,
    Object? startedAt = _copySentinel,
    Object? stoppedAt = _copySentinel,
    List<SessionEvent>? events,
    Object? videoPath = _copySentinel,
    Object? summary = _copySentinel,
    bool clearSummary = false,
    Map<String, Map<Chamber, LogicalKeyboardKey>>? keyMap,
  }) {
    return SessionState(
      protocol: protocol ?? this.protocol,
      isRecording: isRecording ?? this.isRecording,
      startedAt:
          startedAt == _copySentinel ? this.startedAt : startedAt as DateTime?,
      stoppedAt:
          stoppedAt == _copySentinel ? this.stoppedAt : stoppedAt as DateTime?,
      events: events ?? this.events,
      videoPath:
          videoPath == _copySentinel ? this.videoPath : videoPath as String?,
      summary: clearSummary
          ? null
          : summary == _copySentinel
              ? this.summary
              : summary as SessionSummary?,
      keyMap: keyMap ?? this.keyMap,
    );
  }
}

const _copySentinel = Object();

// ============================================================================
// Session Controller: State Management & Recording Logic
// ============================================================================

/// StateNotifier that manages the session lifecycle and event recording.
/// Handles start/stop, event logging, analytics computation, and export.
class SessionController extends StateNotifier<SessionState> {
  SessionController({
    Map<String, Map<Chamber, LogicalKeyboardKey>>? initialKeyMap,
  }) : super(SessionState(
    protocol: Protocol.socialInteraction,
    keyMap: initialKeyMap,
  ));

  void setProtocol(Protocol protocol) {
    state = state.copyWith(protocol: protocol);
  }

  void startSession() {
    if (state.isRecording) {
      return;
    }
    final now = DateTime.now();
    state = state.copyWith(
      isRecording: true,
      startedAt: now,
      stoppedAt: null,
      events: <SessionEvent>[],
      clearSummary: true,
    );
  }

  Future<void> stopSession() async {
    if (!state.isRecording) {
      return;
    }

    final stoppedAt = DateTime.now();
    SessionSummary? summary;
    if (state.events.isNotEmpty) {
      final sessionEnd = stoppedAt.isBefore(state.events.last.timestamp)
          ? state.events.last.timestamp
          : stoppedAt;
      summary = analyzeSession(
        state.events
            .map(
              (event) => ChamberEvent(
                mouseId: event.mouseId,
                chamber: event.chamber,
                timestamp: event.timestamp,
              ),
            )
            .toList(),
        sessionEnd: sessionEnd,
      );
    }

    state = state.copyWith(
      isRecording: false,
      stoppedAt: stoppedAt,
      summary: summary,
    );

    // Save session to history
    if (summary != null) {
      await SessionHistoryDatabase.addSession(
        protocol: state.protocol.label,
        startedAt: state.startedAt!,
        stoppedAt: stoppedAt,
        summary: summary,
      );
    }
  }

  void clearSession() {
    state = SessionState(
      protocol: state.protocol,
      videoPath: state.videoPath,
      keyMap: state.keyMap,
    );
  }

  void logEvent(String mouseId, Chamber chamber) {
    if (!state.isRecording) {
      return;
    }
    final event = SessionEvent(
      mouseId: mouseId,
      chamber: chamber,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      events: <SessionEvent>[...state.events, event],
      clearSummary: true,
    );
  }

  void attachVideo(String? path) {
    state = state.copyWith(videoPath: path);
  }

  String? exportCsv() {
    final summary = state.summary;
    if (summary == null) {
      return null;
    }
    return generateSessionCsv(summary);
  }

  /// Export session summary as a file to disk.
  /// Opens a save dialog and writes CSV data.
  Future<bool> exportSummaryToFile() async {
    final summary = state.summary;
    if (summary == null) {
      return false;
    }

    try {
      final csv = generateSessionCsv(summary);
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];

      final result = await FilePicker.platform.saveFile(
        fileName: 'socialyze_summary_$timestamp.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(csv);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Export session summary as Excel-compatible TSV file.
  /// Exports session summary as Excel-compatible TSV file (.xlsx).
  /// Uses tab-separated values which Excel can open directly.
  /// Adds UTF-8 BOM to ensure Excel recognizes the encoding properly.
  Future<bool> exportSummaryAsExcel() async {
    final summary = state.summary;
    if (summary == null) {
      return false;
    }

    try {
      final tsv = generateSessionExcel(summary);
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];

      final result = await FilePicker.platform.saveFile(
        fileName: 'socialyze_summary_$timestamp.xlsx',
        allowedExtensions: ['xlsx'],
        type: FileType.custom,
      );

      if (result != null) {
        final file = File(result);
        // Write UTF-8 BOM to ensure Excel recognizes the encoding
        await file.writeAsBytes(
          [0xEF, 0xBB, 0xBF, ...utf8.encode(tsv)],
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void setKeyBindings(
    Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap,
  ) {
    state = state.copyWith(keyMap: keyMap);
  }
}

// ============================================================================
// Riverpod Provider: Global Session State Access
// ============================================================================

/// Riverpod provider for the session controller.
/// Provides global access to session state and methods throughout the app.
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController();
});
