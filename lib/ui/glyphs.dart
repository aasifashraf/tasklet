import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// Status glyphs (SPEC §8.3): dashed circle, outline circle, half-filled circle, filled check.
class StatusIcon extends StatelessWidget {
  const StatusIcon(this.status, {super.key, this.size = 14});
  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _StatusPainter(status, t.status(status), t.raised),
    );
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter(this.status, this.color, this.cutout);
  final TaskStatus status;
  final Color color;
  final Color cutout;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fill = Paint()..color = color;
    switch (status) {
      case TaskStatus.backlog:
        const dashes = 8;
        for (var i = 0; i < dashes; i++) {
          final start = i * 2 * math.pi / dashes;
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: r),
            start,
            math.pi / dashes,
            false,
            stroke,
          );
        }
      case TaskStatus.todo:
        canvas.drawCircle(c, r, stroke);
      case TaskStatus.inProgress:
        canvas.drawCircle(c, r, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r - 2.2),
          -math.pi / 2,
          math.pi,
          true,
          fill,
        );
      case TaskStatus.done:
        canvas.drawCircle(c, r + 0.5, fill);
        final check = Path()
          ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
          ..lineTo(c.dx + r * 0.48, c.dy - r * 0.32);
        canvas.drawPath(
          check,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) =>
      old.status != status || old.color != color;
}

/// Priority glyphs (SPEC §8.4): dashes for none, exclamation badge for urgent, bar chart for high/medium/low.
class PriorityIcon extends StatelessWidget {
  const PriorityIcon(this.priority, {super.key, this.size = 14});
  final Priority priority;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = priority == Priority.urgent ? t.warning : t.secondary;
    return CustomPaint(
      size: Size.square(size),
      painter: _PriorityPainter(priority, color, t.tertiary),
    );
  }
}

class _PriorityPainter extends CustomPainter {
  _PriorityPainter(this.priority, this.color, this.muted);
  final Priority priority;
  final Color color;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (priority) {
      case Priority.none:
        final p = Paint()
          ..color = muted
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final x = s * (0.22 + i * 0.28);
          canvas.drawLine(
            Offset(x - s * 0.06, s / 2),
            Offset(x + s * 0.06, s / 2),
            p,
          );
        }
      case Priority.urgent:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.06, s * 0.06, s * 0.88, s * 0.88),
          Radius.circular(s * 0.22),
        );
        canvas.drawRRect(rect, Paint()..color = color);
        final white = Paint()..color = Colors.white;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.44, s * 0.22, s * 0.12, s * 0.36),
            Radius.circular(s * 0.06),
          ),
          white,
        );
        canvas.drawCircle(Offset(s * 0.5, s * 0.72), s * 0.07, white);
      case Priority.high || Priority.medium || Priority.low:
        final filled = switch (priority) {
          Priority.high => 3,
          Priority.medium => 2,
          _ => 1,
        };
        for (var i = 0; i < 3; i++) {
          final h = s * (0.35 + i * 0.25);
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(s * (0.12 + i * 0.3), s * 0.94 - h, s * 0.18, h),
            Radius.circular(s * 0.05),
          );
          canvas.drawRRect(
            rect,
            Paint()
              ..color = i < filled
                  ? color
                  : color.withValues(alpha: color.a * 0.25),
          );
        }
    }
  }

  @override
  bool shouldRepaint(_PriorityPainter old) =>
      old.priority != priority || old.color != color;
}

/// Project glyph: an isometric cube outline, tinted the project color.
class CubeIcon extends StatelessWidget {
  const CubeIcon({super.key, required this.color, this.size = 14});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CubePainter(color));
}

class _CubePainter extends CustomPainter {
  _CubePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round;
    final top = Offset(s * 0.5, s * 0.08);
    final left = Offset(s * 0.1, s * 0.3);
    final right = Offset(s * 0.9, s * 0.3);
    final mid = Offset(s * 0.5, s * 0.52);
    final bl = Offset(s * 0.1, s * 0.72);
    final br = Offset(s * 0.9, s * 0.72);
    final bottom = Offset(s * 0.5, s * 0.94);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..lineTo(bl.dx, bl.dy)
        ..lineTo(left.dx, left.dy)
        ..close()
        ..moveTo(left.dx, left.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(right.dx, right.dy)
        ..moveTo(mid.dx, mid.dy)
        ..lineTo(bottom.dx, bottom.dy),
      p,
    );
  }

  @override
  bool shouldRepaint(_CubePainter old) => old.color != color;
}

/// Saved-view glyph: stacked layers, tinted the view color.
class LayersIcon extends StatelessWidget {
  const LayersIcon({super.key, required this.color, this.size = 14});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LayersPainter(color));
}

class _LayersPainter extends CustomPainter {
  _LayersPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.5, s * 0.1)
        ..lineTo(s * 0.92, s * 0.32)
        ..lineTo(s * 0.5, s * 0.54)
        ..lineTo(s * 0.08, s * 0.32)
        ..close(),
      p,
    );
    for (final y in [0.54, 0.76]) {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.08, s * y)
          ..lineTo(s * 0.5, s * (y + 0.22))
          ..lineTo(s * 0.92, s * y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_LayersPainter old) => old.color != color;
}

/// A small solid color dot (labels).
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 8, this.border});
  final Color color;
  final double size;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: border == null ? null : Border.all(color: border!, width: 1.5),
    ),
  );
}
