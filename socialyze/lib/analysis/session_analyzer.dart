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

/// Generates a CSV export combining per-mouse summaries and raw events.
String generateSessionCsv(SessionSummary summary) {
  final buffer = StringBuffer()
    ..writeln(
      'type,mouse,chamber,duration_seconds,switch_count,timestamp_iso8601',
    );

  summary.mouseSummaries.forEach((mouseId, mouseSummary) {
    for (final chamber in Chamber.values) {
      final duration = mouseSummary.dwellTime(chamber);
      final seconds = duration.inMilliseconds / 1000;
      buffer.writeln(
        'summary,$mouseId,${chamber.name},${seconds.toStringAsFixed(3)},,',
      );
    }
    buffer.writeln(
      'summary,$mouseId,total,,${mouseSummary.switchCount},',
    );
  });

  for (final event in summary.events) {
    buffer.writeln(
      'event,${event.mouseId},${event.chamber.name},,,${event.timestamp.toIso8601String()}',
    );
  }

  return buffer.toString();
}
