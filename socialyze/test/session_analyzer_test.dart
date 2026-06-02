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

    test('mouseSessionEnds caps each mouse independently', () {
      final start = DateTime(2024, 1, 1, 12, 0, 0);
      // Mouse A released at t=0, Mouse B released 5 min later. The global
      // session runs 15 min, but each mouse should be capped at 10 min from
      // its own release.
      final events = [
        ChamberEvent(mouseId: 'A', chamber: Chamber.middle, timestamp: start),
        ChamberEvent(
          mouseId: 'B',
          chamber: Chamber.middle,
          timestamp: start.add(const Duration(minutes: 5)),
        ),
      ];

      final summary = analyzeSession(
        events,
        sessionEnd: start.add(const Duration(minutes: 15)),
        mouseSessionEnds: {
          'A': start.add(const Duration(minutes: 10)),
          'B': start.add(const Duration(minutes: 15)),
        },
      );

      // Each mouse accrues exactly its 10-minute window, not the full 15.
      expect(
        summary.mouseSummaries['A']?.totalDwell,
        const Duration(minutes: 10),
      );
      expect(
        summary.mouseSummaries['B']?.totalDwell,
        const Duration(minutes: 10),
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

    test('rejects logging the same chamber twice as a likely mistake', () {
      final controller = SessionController()..startSession();

      expect(
        controller.logEvent('Mouse A', Chamber.middle),
        LogResult.recorded,
      );
      // Re-logging the same chamber is blocked and not recorded.
      expect(
        controller.logEvent('Mouse A', Chamber.middle),
        LogResult.sameChamber,
      );
      expect(controller.state.events.length, 1);

      // A real move is still accepted afterwards.
      expect(
        controller.logEvent('Mouse A', Chamber.stranger),
        LogResult.recorded,
      );
      expect(controller.state.events.length, 2);
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

      // Column order stays fixed; only the chamber feeding each column moves.
      expect(
        csv,
        contains('Mouse ID,Empty (s),Middle (s),Stranger (s)'),
      );
      // With the swap on, the 30s of internal "empty" dwell was observed as the
      // Stranger chamber, so it belongs under Stranger (s); the Empty (s) column
      // shows the (zero) internal-stranger dwell.
      expect(csv, contains('A,0.000,15.000,30.000'));
    });
  });
}
