import 'package:flutter_test/flutter_test.dart';
import 'package:socialyze/analysis/session_analyzer.dart';

void main() {
  group('analyzeSession', () {
    test('computes dwell times and switches per mouse', () {
      final start = DateTime(2024, 1, 1, 12, 0, 0);
      final events = [
        ChamberEvent(mouseId: 'A', chamber: Chamber.empty, timestamp: start),
        ChamberEvent(
          mouseId: 'A',
          chamber: Chamber.middle,
          timestamp: start.add(const Duration(seconds: 30)),
        ),
        ChamberEvent(
          mouseId: 'A',
          chamber: Chamber.stranger,
          timestamp: start.add(const Duration(seconds: 50)),
        ),
        ChamberEvent(
          mouseId: 'B',
          chamber: Chamber.middle,
          timestamp: start.add(const Duration(seconds: 10)),
        ),
        ChamberEvent(
          mouseId: 'B',
          chamber: Chamber.empty,
          timestamp: start.add(const Duration(seconds: 40)),
        ),
      ];

      final summary = analyzeSession(
        events,
        sessionEnd: start.add(const Duration(seconds: 80)),
      );

      expect(summary.mouseSummaries['A']?.switchCount, 2);
      expect(
        summary.mouseSummaries['A']?.dwellTime(Chamber.empty),
        const Duration(seconds: 30),
      );
      expect(
        summary.mouseSummaries['A']?.dwellTime(Chamber.middle),
        const Duration(seconds: 20),
      );
      expect(
        summary.mouseSummaries['A']?.dwellTime(Chamber.stranger),
        const Duration(seconds: 30),
      );

      expect(summary.mouseSummaries['B']?.switchCount, 1);
      expect(
        summary.mouseSummaries['B']?.dwellTime(Chamber.middle),
        const Duration(seconds: 30),
      );
      expect(
        summary.mouseSummaries['B']?.dwellTime(Chamber.empty),
        const Duration(seconds: 40),
      );
      expect(
        summary.mouseSummaries['B']?.dwellTime(Chamber.stranger),
        const Duration.zero,
      );
    });

    test('throws when session end precedes last event', () {
      final start = DateTime(2024, 1, 1, 12, 0, 0);
      final events = [
        ChamberEvent(mouseId: 'A', chamber: Chamber.empty, timestamp: start),
        ChamberEvent(
          mouseId: 'A',
          chamber: Chamber.middle,
          timestamp: start.add(const Duration(seconds: 10)),
        ),
      ];

      expect(
        () => analyzeSession(
          events,
          sessionEnd: start.add(const Duration(seconds: 5)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('generateSessionCsv', () {
    test('combines summaries and events into export', () {
      final start = DateTime(2024, 1, 1, 12);
      final events = [
        ChamberEvent(mouseId: 'A', chamber: Chamber.empty, timestamp: start),
        ChamberEvent(
          mouseId: 'A',
          chamber: Chamber.middle,
          timestamp: start.add(const Duration(seconds: 30)),
        ),
      ];

      final summary = analyzeSession(
        events,
        sessionEnd: start.add(const Duration(seconds: 45)),
      );

      final csv = generateSessionCsv(summary);

      expect(csv.split('\n').first, contains('type,mouse,chamber'));
      expect(csv, contains('summary,A,empty,30.000'));
      expect(csv, contains('summary,A,total,,1'));
      expect(csv, contains('event,A,middle,,,${events.last.timestamp.toIso8601String()}'));
    });
  });
}
