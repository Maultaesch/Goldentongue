import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

class ScoreRing extends StatelessWidget {
  final int value;
  final String label;
  const ScoreRing({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: 84,
        height: 84,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value / 100,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: AppColors.goldPremium,
              backgroundColor: const Color(0x1AFFFFFF),
            ),
          ),
          Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.gold, fontSize: 26)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class RadarChart extends StatelessWidget {
  final List<String> labels;
  final List<int> values;
  const RadarChart({super.key, required this.labels, required this.values});

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.1,
        child: CustomPaint(painter: _RadarPainter(labels, values)),
      );
}

class _RadarPainter extends CustomPainter {
  final List<String> labels;
  final List<int> values;
  _RadarPainter(this.labels, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 36;
    Offset pt(int i, double f) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * f;
    }

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x1FFFFFFF);
    for (final f in [.25, .5, .75, 1.0]) {
      final path = Path()..moveTo(pt(0, f).dx, pt(0, f).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(pt(i, f).dx, pt(i, f).dy);
      }
      canvas.drawPath(path..close(), grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, pt(i, 1), grid);
    }
    final poly = Path()..moveTo(pt(0, values[0] / 100).dx, pt(0, values[0] / 100).dy);
    for (var i = 1; i < n; i++) {
      poly.lineTo(pt(i, values[i] / 100).dx, pt(i, values[i] / 100).dy);
    }
    poly.close();
    canvas.drawPath(poly, Paint()..color = const Color(0x4DD4AF37));
    canvas.drawPath(
      poly,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.goldPremium,
    );
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = pt(i, 1.2);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.values != values;
}
