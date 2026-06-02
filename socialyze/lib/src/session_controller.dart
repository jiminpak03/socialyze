import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/session_analyzer.dart';
import 'session_database.dart';
import 'settings_store.dart';

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

/// Default per-mouse key columns, ordered as [empty, middle, stranger].
///
/// The first three mice use the numpad columns (7/4/1, 8/5/2, 9/6/3). Studies
/// that score more than three mice fall back to letter columns so additional
/// mice still get sensible, non-conflicting defaults; any of these can be
/// remapped from the "Remap shortcuts" dialog.
const List<List<LogicalKeyboardKey>> _defaultKeyColumns = [
  [LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad1],
  [LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad2],
  [LogicalKeyboardKey.numpad9, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad3],
  [LogicalKeyboardKey.keyR, LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyV],
  [LogicalKeyboardKey.keyT, LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyB],
  [LogicalKeyboardKey.keyY, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyN],
];

const List<Chamber> _defaultChamberOrder = [
  Chamber.empty,
  Chamber.middle,
  Chamber.stranger,
];

/// Generates default key bindings for an arbitrary number of mice.
///
/// Mice beyond the predefined columns receive empty binding maps, which the
/// user can fill in via the remap dialog.
Map<String, Map<Chamber, LogicalKeyboardKey>> _generateDefaultKeyBindings(
  List<String> mouseIds,
) {
  final map = <String, Map<Chamber, LogicalKeyboardKey>>{};
  for (var mouseIndex = 0; mouseIndex < mouseIds.length; mouseIndex++) {
    final chambers = <Chamber, LogicalKeyboardKey>{};
    if (mouseIndex < _defaultKeyColumns.length) {
      final column = _defaultKeyColumns[mouseIndex];
      for (var chamberIndex = 0;
          chamberIndex < _defaultChamberOrder.length;
          chamberIndex++) {
        chambers[_defaultChamberOrder[chamberIndex]] = column[chamberIndex];
      }
    }
    map[mouseIds[mouseIndex]] = chambers;
  }
  return map;
}

/// Public wrapper so the UI can regenerate default bindings for any roster of
/// mice (e.g. after the count changes or "reset to defaults" is pressed).
Map<String, Map<Chamber, LogicalKeyboardKey>> generateDefaultKeyBindings(
  List<String> mouseIds,
) =>
    _generateDefaultKeyBindings(mouseIds);

/// Default bindings for a single mouse at [mouseIndex] (used when adding mice).
Map<Chamber, LogicalKeyboardKey> defaultBindingsForIndex(int mouseIndex) {
  final chambers = <Chamber, LogicalKeyboardKey>{};
  if (mouseIndex >= 0 && mouseIndex < _defaultKeyColumns.length) {
    final column = _defaultKeyColumns[mouseIndex];
    for (var i = 0; i < _defaultChamberOrder.length; i++) {
      chambers[_defaultChamberOrder[i]] = column[i];
    }
  }
  return chambers;
}

/// Outcome of attempting to log a chamber entry.
enum LogResult {
  /// Event was recorded.
  recorded,

  /// Ignored because no session is currently recording.
  notRecording,

  /// Rejected: the mouse cannot move between the two outer chambers
  /// without passing through the middle chamber first.
  impossibleMove,
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
    required this.position,
  });

  final String mouseId;
  final Chamber chamber;

  /// Wall-clock time the key was pressed (kept for reference/debugging).
  final DateTime timestamp;

  /// Position within the video when the event was logged. This is the basis
  /// for all dwell-time analytics so results are independent of playback speed.
  final Duration position;
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
    this.swapOuterChambers = false,
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

  /// When true, the two outer chambers are relabelled (Empty <-> Stranger) so
  /// the UI matches a video whose chamber orientation is flipped. Purely a
  /// display concern — the recorded chamber identities are unchanged.
  final bool swapOuterChambers;

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
    bool? swapOuterChambers,
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
      swapOuterChambers: swapOuterChambers ?? this.swapOuterChambers,
      keyMap: keyMap ?? this.keyMap,
    );
  }
}

const _copySentinel = Object();

/// Fixed reference instant used to convert a video [Duration] position into a
/// [DateTime] so the existing [analyzeSession] logic (which operates on
/// timestamps) can compute video-time dwell durations without modification.
final DateTime _videoEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime _positionToTimestamp(Duration position) =>
    _videoEpoch.add(position.isNegative ? Duration.zero : position);

/// Physical left-to-right ordering of the arena chambers.
/// The middle chamber separates the two outer chambers, so a mouse can only
/// move to an adjacent chamber.
int _chamberPosition(Chamber chamber) {
  switch (chamber) {
    case Chamber.empty:
      return 0;
    case Chamber.middle:
      return 1;
    case Chamber.stranger:
      return 2;
  }
}

/// True when moving from [from] to [to] would skip the middle chamber, which
/// is physically impossible in a three-chamber arena.
bool _isImpossibleTransition(Chamber from, Chamber to) {
  return (_chamberPosition(from) - _chamberPosition(to)).abs() > 1;
}

// ============================================================================
// Session Controller: State Management & Recording Logic
// ============================================================================

/// StateNotifier that manages the session lifecycle and event recording.
/// Handles start/stop, event logging, analytics computation, and export.
class SessionController extends StateNotifier<SessionState> {
  SessionController({
    Map<String, Map<Chamber, LogicalKeyboardKey>>? initialKeyMap,
    bool initialSwapOuterChambers = false,
  }) : super(SessionState(
    protocol: Protocol.socialInteraction,
    keyMap: initialKeyMap,
    swapOuterChambers: initialSwapOuterChambers,
  ));

  /// Supplies the current playback position of the loaded video. Registered by
  /// the video panel once a player exists. Events are timestamped with this so
  /// dwell times reflect *video time* regardless of playback speed or pauses.
  Duration Function()? _videoPositionProvider;

  void setVideoPositionProvider(Duration Function()? provider) {
    _videoPositionProvider = provider;
  }

  Duration get _currentVideoPosition =>
      _videoPositionProvider?.call() ?? Duration.zero;

  void setProtocol(Protocol protocol) {
    state = state.copyWith(protocol: protocol);
  }

  void setSwapOuterChambers(bool value) {
    state = state.copyWith(swapOuterChambers: value);
    SettingsStore.setSwapOuterChambers(value);
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
      // Analytics run on *video time*: each event's video position is mapped
      // onto a fixed epoch so the analyzer's delta math yields durations that
      // are independent of playback speed. The session ends at the latest of
      // the current playback position or the last logged event.
      final endPosition = state.events
          .map((e) => e.position)
          .fold<Duration>(_currentVideoPosition,
              (max, p) => p > max ? p : max);

      summary = analyzeSession(
        state.events
            .map(
              (event) => ChamberEvent(
                mouseId: event.mouseId,
                chamber: event.chamber,
                timestamp: _positionToTimestamp(event.position),
              ),
            )
            .toList(),
        sessionEnd: _positionToTimestamp(endPosition),
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

  LogResult logEvent(String mouseId, Chamber chamber) {
    if (!state.isRecording) {
      return LogResult.notRecording;
    }
    final lastChamber = _lastChamberFor(mouseId);
    if (lastChamber != null && _isImpossibleTransition(lastChamber, chamber)) {
      return LogResult.impossibleMove;
    }
    final event = SessionEvent(
      mouseId: mouseId,
      chamber: chamber,
      timestamp: DateTime.now(),
      position: _currentVideoPosition,
    );
    state = state.copyWith(
      events: <SessionEvent>[...state.events, event],
      clearSummary: true,
    );
    return LogResult.recorded;
  }

  /// Most recently logged chamber for [mouseId] in the current session,
  /// or null if the mouse has no events yet.
  Chamber? _lastChamberFor(String mouseId) {
    for (var i = state.events.length - 1; i >= 0; i--) {
      if (state.events[i].mouseId == mouseId) {
        return state.events[i].chamber;
      }
    }
    return null;
  }

  void attachVideo(String? path) {
    state = state.copyWith(videoPath: path);
  }

  /// Export session summary as a file to disk.
  /// Opens a save dialog and writes CSV data.
  Future<bool> exportSummaryToFile() async {
    final summary = state.summary;
    if (summary == null) {
      return false;
    }

    try {
      final csv = generateSessionCsv(
        summary,
        swapOuterChambers: state.swapOuterChambers,
      );
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

  void setKeyBindings(
    Map<String, Map<Chamber, LogicalKeyboardKey>> keyMap,
  ) {
    state = state.copyWith(keyMap: keyMap);
    SettingsStore.setKeyMap(keyMap);
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
