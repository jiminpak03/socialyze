import 'package:flutter_test/flutter_test.dart';
import 'package:socialyze/analysis/session_analyzer.dart';
import 'package:socialyze/src/session_controller.dart';

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
        Duration.zero,
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

  group('SessionController.logEvent chamber-movement validation', () {
    test('rejects moving between outer chambers without the middle', () {
      final controller = SessionController()..startSession();

      expect(controller.logEvent('Mouse A', Chamber.empty), LogResult.recorded);
      expect(
        controller.logEvent('Mouse A', Chamber.stranger),
        LogResult.impossibleMove,
      );
      // The impossible event must not be recorded.
      expect(controller.state.events.length, 1);
    });

    test('allows adjacent moves through the middle chamber', () {
      final controller = SessionController()..startSession();

      expect(controller.logEvent('Mouse A', Chamber.empty), LogResult.recorded);
      expect(
        controller.logEvent('Mouse A', Chamber.middle),
        LogResult.recorded,
      );
      expect(
        controller.logEvent('Mouse A', Chamber.stranger),
        LogResult.recorded,
      );
      expect(controller.state.events.length, 3);
    });

    test('validates each mouse independently', () {
      final controller = SessionController()..startSession();

      controller.logEvent('Mouse A', Chamber.empty);
      // A different mouse starting in stranger is fine.
      expect(
        controller.logEvent('Mouse B', Chamber.stranger),
        LogResult.recorded,
      );
      // But Mouse A still cannot jump empty -> stranger.
      expect(
        controller.logEvent('Mouse A', Chamber.stranger),
        LogResult.impossibleMove,
      );
    });

    test('ignores events when not recording', () {
      final controller = SessionController();
      expect(
        controller.logEvent('Mouse A', Chamber.empty),
        LogResult.notRecording,
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

      expect(csv, contains('Session Summary Report'));
      expect(csv, contains('Total Duration'));
      expect(csv, contains('Mouse ID'));
      expect(csv, contains('Empty (s)'));
      expect(csv, contains('Stranger (s)'));
      expect(csv, contains('A,')); // Mouse ID row
      expect(csv, contains('30.000')); // Empty dwell time
      expect(csv, contains('1')); // Switch count
    });

    test('swapOuterChambers relabels outer columns', () {
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

      final csv = generateSessionCsv(summary, swapOuterChambers: true);

      // Header order swaps so the Stranger column now leads.
      expect(
        csv,
        contains('Mouse ID,Stranger (s),Middle (s),Empty (s)'),
      );
      // Values follow their relabelled columns: the leading Stranger column
      // shows 0s (no stranger dwell) and the trailing Empty column shows 30s.
      expect(csv, contains('A,0.000,15.000,30.000'));
    });
  });
}
