import 'package:flutter/material.dart';
import '../analysis/session_analyzer.dart';
import 'session_controller.dart' show Protocol;

// ============================================================================
// Chamber Visualization: Donut Chart Display of Dwell Times
// ============================================================================

/// Displays chamber dwell times visually as a circle diagram.
/// Shows percentage of time spent in each chamber with color-coded segments.
class ChamberVisualization extends StatelessWidget {
  const ChamberVisualization({
    required this.summary,
    required this.protocol,
    super.key,
  });

  final MouseSummary summary;
  final Protocol protocol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = summary.totalDwell.inMilliseconds;

    if (total == 0) {
      return Center(
        child: Text(
          'No dwell time recorded',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      );
    }

    // Calculate percentages and colors for each chamber
    final empty = summary.dwellTime(Chamber.empty).inMilliseconds / total;
    final middle = summary.dwellTime(Chamber.middle).inMilliseconds / total;
    final stranger = summary.dwellTime(Chamber.stranger).inMilliseconds / total;

    const emptyColor = Color(0xFF8E7CC3); // Purple
    const middleColor = Color(0xFF5FC3E4); // Blue
    const strangerColor = Color(0xFFE8865A); // Orange

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular pie chart
          SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: _ChamberPainter(
                emptyPercent: empty,
                middlePercent: middle,
                strangerPercent: stranger,
                emptyColor: emptyColor,
                middleColor: middleColor,
                strangerColor: strangerColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendItem(
                color: emptyColor,
                label: _chamberLabel(protocol, Chamber.empty),
                percentage: (empty * 100).toStringAsFixed(1),
              ),
              _LegendItem(
                color: middleColor,
                label: _chamberLabel(protocol, Chamber.middle),
                percentage: (middle * 100).toStringAsFixed(1),
              ),
              _LegendItem(
                color: strangerColor,
                label: _chamberLabel(protocol, Chamber.stranger),
                percentage: (stranger * 100).toStringAsFixed(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Chamber Painter: Custom Paint Donut Chart Renderer
// ============================================================================

class _ChamberPainter extends CustomPainter {
  _ChamberPainter({
    required this.emptyPercent,
    required this.middlePercent,
    required this.strangerPercent,
    required this.emptyColor,
    required this.middleColor,
    required this.strangerColor,
  });

  final double emptyPercent;
  final double middlePercent;
  final double strangerPercent;
  final Color emptyColor;
  final Color middleColor;
  final Color strangerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    var startAngle = -90.0; // Start from top

    // Draw empty chamber segment
    _drawSegment(
      canvas,
      center,
      radius,
      startAngle,
      emptyPercent * 360,
      emptyColor,
    );
    startAngle += emptyPercent * 360;

    // Draw middle chamber segment
    _drawSegment(
      canvas,
      center,
      radius,
      startAngle,
      middlePercent * 360,
      middleColor,
    );
    startAngle += middlePercent * 360;

    // Draw stranger chamber segment
    _drawSegment(
      canvas,
      center,
      radius,
      startAngle,
      strangerPercent * 360,
      strangerColor,
    );

    // Draw center circle for donut effect
    canvas.drawCircle(
      center,
      radius * 0.4,
      Paint()..color = Colors.white,
    );
  }

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double radius,
    double startAngle,
    double sweepAngle,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _degreesToRadians(startAngle),
      _degreesToRadians(sweepAngle),
      true,
      paint,
    );
  }

  double _degreesToRadians(double degrees) {
    return degrees * 3.14159265359 / 180;
  }

  @override
  bool shouldRepaint(_ChamberPainter oldDelegate) {
    return oldDelegate.emptyPercent != emptyPercent ||
        oldDelegate.middlePercent != middlePercent ||
        oldDelegate.strangerPercent != strangerPercent;
  }
}

// ============================================================================
// Legend Item: Color-Coded Chamber Label Display
// ============================================================================

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.percentage,
  });

  final Color color;
  final String label;
  final String percentage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('$label: $percentage%'),
        ],
      ),
    );
  }
}

String _chamberLabel(Protocol protocol, Chamber chamber) {
  switch (protocol) {
    case Protocol.socialInteraction:
      switch (chamber) {
        case Chamber.empty:
          return 'Empty';
        case Chamber.middle:
          return 'Middle';
        case Chamber.stranger:
          return 'Stranger';
      }
    case Protocol.socialNovelty:
      switch (chamber) {
        case Chamber.empty:
          return 'New Stranger';
        case Chamber.middle:
          return 'Middle';
        case Chamber.stranger:
          return 'Stranger';
      }
  }
}
