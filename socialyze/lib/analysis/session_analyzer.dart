import 'dart:collection';

/// Identifiers for the three chambers in the social interaction arena.
enum Chamber {
  empty,
  middle,
  stranger,
}

/// Immutable record of a mouse entering a chamber at a specific timestamp.
class ChamberEvent {
  ChamberEvent({
    required this.mouseId,
    required this.chamber,
    required this.timestamp,
  });

  final String mouseId;
  final Chamber chamber;
  final DateTime timestamp;
}

/// Summary metrics calculated for a single mouse across an entire session.
class MouseSummary {
  MouseSummary({
    required this.mouseId,
    required Map<Chamber, Duration> dwellDurations,
    required this.switchCount,
    required this.firstEvent,
    required this.lastEvent,
  }) : _dwellDurations = Map<Chamber, Duration>.unmodifiable(dwellDurations);

  final String mouseId;
  final int switchCount;
  final DateTime firstEvent;
  final DateTime lastEvent;
  final Map<Chamber, Duration> _dwellDurations;

  /// Returns the total time the mouse spent inside [chamber].
  Duration dwellTime(Chamber chamber) =>
      _dwellDurations[chamber] ?? Duration.zero;

  /// Total time the mouse spent in the arena across all chambers.
  Duration get totalDwell => _dwellDurations.values.fold<Duration>(
        Duration.zero,
        (previous, duration) => previous + duration,
      );

  Map<Chamber, Duration> get dwellDurations => _dwellDurations;
}

/// Container for the full session analytics across all mice.
class SessionSummary {
  SessionSummary({
    required this.sessionStart,
    required this.sessionEnd,
    required Map<String, MouseSummary> mouseSummaries,
    required List<ChamberEvent> events,
  })  : mouseSummaries = UnmodifiableMapView(mouseSummaries),
        events = UnmodifiableListView(events);

  final DateTime sessionStart;
  final DateTime sessionEnd;
  final Map<String, MouseSummary> mouseSummaries;
  final List<ChamberEvent> events;

  Duration get duration => sessionEnd.difference(sessionStart);
}

/// Computes dwell times, switch counts and supporting metadata for a session.
SessionSummary analyzeSession(
  List<ChamberEvent> events, {
  required DateTime sessionEnd,
}) {
  if (events.isEmpty) {
    throw ArgumentError('At least one event is required to analyze a session.');
  }

  final sortedEvents = List<ChamberEvent>.from(events)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final sessionStart = sortedEvents.first.timestamp;

  if (sessionEnd.isBefore(sessionStart)) {
    throw ArgumentError('Session end must be after the first event.');
  }

  final grouped = <String, List<ChamberEvent>>{};
  for (final event in sortedEvents) {
    grouped.putIfAbsent(event.mouseId, () => <ChamberEvent>[]).add(event);
  }

  final summaries = <String, MouseSummary>{};

  grouped.forEach((mouseId, mouseEvents) {
    mouseEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (mouseEvents.first.timestamp.isAfter(mouseEvents.last.timestamp)) {
      throw ArgumentError('Invalid timestamps for mouse $mouseId.');
    }

    if (sessionEnd.isBefore(mouseEvents.last.timestamp)) {
      throw ArgumentError(
        'Session end must be after the last event for mouse $mouseId.',
      );
    }

    final dwellDurations = {
      for (final chamber in Chamber.values) chamber: Duration.zero,
    };

    var switchCount = 0;
    var previousEvent = mouseEvents.first;

    for (final event in mouseEvents.skip(1)) {
      final delta = event.timestamp.difference(previousEvent.timestamp);
      if (delta.isNegative) {
        throw ArgumentError('Events must be provided in chronological order.');
      }
      dwellDurations[previousEvent.chamber] =
          dwellDurations[previousEvent.chamber]! + delta;
      if (event.chamber != previousEvent.chamber) {
        switchCount++;
      }
      previousEvent = event;
    }

    final tailDuration = sessionEnd.difference(previousEvent.timestamp);
    if (tailDuration.isNegative) {
      throw ArgumentError('Session end must be after the last event.');
    }
    dwellDurations[previousEvent.chamber] =
        dwellDurations[previousEvent.chamber]! + tailDuration;

    summaries[mouseId] = MouseSummary(
      mouseId: mouseId,
      dwellDurations: dwellDurations,
      switchCount: switchCount,
      firstEvent: mouseEvents.first.timestamp,
      lastEvent: sessionEnd,
    );
  });

  return SessionSummary(
    sessionStart: sessionStart,
    sessionEnd: sessionEnd,
    mouseSummaries: summaries,
    events: sortedEvents,
  );
}

/// Generates a CSV export with session summary data in a clean, organized format.
///
/// All durations are measured in *video time* (derived from the video's
/// playback position), so they are unaffected by the playback speed used while
/// scoring. When [swapOuterChambers] is true the Empty and Stranger columns are
/// relabelled to match a video whose chamber orientation is flipped; the
/// underlying values follow their labels so the export matches what was shown
/// on screen.
String generateSessionCsv(
  SessionSummary summary, {
  bool swapOuterChambers = false,
}) {
  final buffer = StringBuffer();

  // Header section
  buffer.writeln('Session Summary Report');
  buffer.writeln('');

  // Session metadata (durations are video-time seconds)
  buffer.writeln('Total Duration,${_formatDuration(summary.duration)}');
  buffer.writeln('');

  final firstLabel = swapOuterChambers ? 'Stranger (s)' : 'Empty (s)';
  final lastLabel = swapOuterChambers ? 'Empty (s)' : 'Stranger (s)';

  // Summary statistics per mouse - in spreadsheet-friendly format
  buffer.writeln(
    'Mouse ID,$firstLabel,Middle (s),$lastLabel,Total Dwell (s),Switch Count',
  );

  for (final entry in summary.mouseSummaries.entries) {
    final mouseId = entry.key;
    final mouseSummary = entry.value;

    // The first/last columns track the chamber currently shown under that
    // label, so a swap relabels the column without moving the recorded value.
    final firstChamber = swapOuterChambers ? Chamber.stranger : Chamber.empty;
    final lastChamber = swapOuterChambers ? Chamber.empty : Chamber.stranger;

    final firstDwell = mouseSummary.dwellTime(firstChamber).inMilliseconds / 1000;
    final middleDwell = mouseSummary.dwellTime(Chamber.middle).inMilliseconds / 1000;
    final lastDwell = mouseSummary.dwellTime(lastChamber).inMilliseconds / 1000;
    final totalDwell = mouseSummary.totalDwell.inMilliseconds / 1000;

    buffer.writeln(
      '$mouseId,${firstDwell.toStringAsFixed(3)},${middleDwell.toStringAsFixed(3)},${lastDwell.toStringAsFixed(3)},${totalDwell.toStringAsFixed(3)},${mouseSummary.switchCount}',
    );
  }

  return buffer.toString();
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write(hours.toString().padLeft(2, '0'));
    buffer.write('h ');
  }
  buffer.write(minutes.toString().padLeft(2, '0'));
  buffer.write('m ');
  buffer.write(seconds.toString().padLeft(2, '0'));
  buffer.write('s');
  return buffer.toString();
}
