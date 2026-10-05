import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class EsdmEvolucaoPoint {
  final String label;
  final double averageSupport;

  const EsdmEvolucaoPoint({
    required this.label,
    required this.averageSupport,
  });
}

/// Gráfico leve, sem dependência externa, para acompanhar a autonomia média.
class EsdmEvolucaoChart extends StatelessWidget {
  final List<EsdmEvolucaoPoint> points;

  const EsdmEvolucaoChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(child: Text('Ainda não há semanas com registros.')),
      );
    }

    return SizedBox(
      height: 280,
      width: double.infinity,
      child: CustomPaint(
        painter: _EsdmEvolucaoPainter(points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EsdmEvolucaoPainter extends CustomPainter {
  final List<EsdmEvolucaoPoint> points;

  _EsdmEvolucaoPainter(this.points);

  static const _left = 42.0;
  static const _top = 18.0;
  static const _right = 16.0;
  static const _bottom = 42.0;
  static const _maxValue = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = math.max(1, size.width - _left - _right).toDouble();
    final chartHeight = math.max(1, size.height - _top - _bottom).toDouble();
    final origin = Offset(_left, _top + chartHeight);
    final paintGrid = Paint()
      ..color = AppTheme.cardBorder
      ..strokeWidth = 1;
    final paintAxis = Paint()
      ..color = AppTheme.mutedText
      ..strokeWidth = 1.2;

    canvas.drawLine(origin, Offset(_left, _top), paintAxis);
    canvas.drawLine(origin, Offset(_left + chartWidth, origin.dy), paintAxis);

    for (var level = 0; level <= 3; level++) {
      final y = _top + chartHeight - (level / _maxValue) * chartHeight;
      canvas.drawLine(
        Offset(_left, y),
        Offset(_left + chartWidth, y),
        paintGrid,
      );
      _drawText(
        canvas,
        '$level',
        Offset(8, y - 7),
        const TextStyle(fontSize: 11, color: AppTheme.mutedText),
      );
    }

    final pointsInPixels = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? _left + chartWidth / 2
          : _left + (index / (points.length - 1)) * chartWidth;
      final normalized = (points[index].averageSupport / _maxValue).clamp(0.0, 1.0);
      final y = _top + chartHeight - normalized * chartHeight;
      pointsInPixels.add(Offset(x, y));
    }

    final line = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var index = 0; index < pointsInPixels.length; index++) {
      final point = pointsInPixels[index];
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, line);

    final dot = Paint()..color = AppTheme.primary;
    final dotInner = Paint()..color = Colors.white;
    for (var index = 0; index < pointsInPixels.length; index++) {
      final point = pointsInPixels[index];
      canvas.drawCircle(point, 6, dot);
      canvas.drawCircle(point, 2.5, dotInner);
      final labelWidth = points[index].label.length * 6.5;
      _drawText(
        canvas,
        points[index].label,
        Offset(point.dx - labelWidth / 2, _top + chartHeight + 12),
        const TextStyle(fontSize: 10, color: AppTheme.mutedText),
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _EsdmEvolucaoPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    for (var index = 0; index < points.length; index++) {
      if (oldDelegate.points[index].label != points[index].label ||
          oldDelegate.points[index].averageSupport !=
              points[index].averageSupport) {
        return true;
      }
    }
    return false;
  }
}
