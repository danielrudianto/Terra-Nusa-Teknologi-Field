import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/util/format.dart';
import 'calc/cut_plan.dart';
import 'calc/pile_snapshot.dart';

/// Live cross-section of the hole: concrete so far, where this truck should
/// bring it, cut-off, and where the tremie hangs.
///
/// Drawn to scale in DEPTH (the hole's width is not to scale). While a truck
/// pours, the concrete level is an estimate and is labelled so; the moving
/// stripes in the tremie only mean "concrete is flowing".
class PileSectionView extends StatefulWidget {
  const PileSectionView({super.key, required this.snapshot, required this.pouring, required this.paused});

  final PileSnapshot snapshot;
  final bool pouring;
  final bool paused;

  @override
  State<PileSectionView> createState() => _PileSectionViewState();
}

class _PileSectionViewState extends State<PileSectionView> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  bool get _live => widget.pouring && !widget.paused;

  @override
  void initState() {
    super.initState();
    if (_live) _flow.repeat();
  }

  /// Animate only while concrete flows: a still picture costs no battery.
  @override
  void didUpdateWidget(PileSectionView old) {
    super.didUpdateWidget(old);
    if (_live && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!_live && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final s = widget.snapshot;
    final live = _live;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: w.surface, borderRadius: BorderRadius.circular(16), boxShadow: w.shadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.vertical_split_outlined, size: 18, color: w.brand),
              const SizedBox(width: 8),
              Expanded(child: Text('Penampang lubang', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: w.ink))),
              if (!s.concreteMeasured)
                Text('muka beton perkiraan', style: TextStyle(fontSize: 12, color: w.warnFg, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 340,
            // Smooth moves when the level or the tremie changes.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: s.concreteNowM),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, level, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: s.tremieBottomM),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, tremieEnd, _) => AnimatedBuilder(
                  animation: _flow,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _SectionPainter(
                      s: s,
                      concreteNowM: level,
                      tremieBottomM: tremieEnd,
                      phase: live ? _flow.value : 0,
                      live: live,
                      colors: w,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPainter extends CustomPainter {
  _SectionPainter({
    required this.s,
    required this.concreteNowM,
    required this.tremieBottomM,
    required this.phase,
    required this.live,
    required this.colors,
  });

  final PileSnapshot s;
  final double concreteNowM;
  final double tremieBottomM;
  final double phase;
  final bool live;
  final TerraColors colors;

  static const _soil = Color(0xFFE6DCCB);
  static const _soilLine = Color(0xFFCDBFA6);
  static const _slurry = Color(0xFFDCE6EF);
  static const _concrete = Color(0xFF9EA5AF);
  static const _concreteTop = Color(0xFFB9BFC7);

  @override
  void paint(Canvas canvas, Size size) {
    const top = 30.0; // room above ground for the hopper
    const left = 40.0; // depth scale
    const labelsW = 128.0;
    final holeW = math.min(72.0, (size.width - left - labelsW) * 0.45);
    final cx = left + (size.width - left - labelsW) / 2;
    final holeL = cx - holeW / 2, holeR = cx + holeW / 2;
    final maxDepth = s.bottomDepthM + 0.8;
    double y(double depth) => top + depth / maxDepth * (size.height - top - 6);

    // --- ground and hole ---------------------------------------------------
    canvas.drawRect(Rect.fromLTRB(holeL - 34, y(0), holeR + 34, size.height), Paint()..color = _soil);
    for (var d = 2.0; d < maxDepth; d += 2.5) {
      canvas.drawLine(Offset(holeL - 34, y(d)), Offset(holeL - 6, y(d) + 6), Paint()..color = _soilLine..strokeWidth = 1);
      canvas.drawLine(Offset(holeR + 6, y(d) + 3), Offset(holeR + 34, y(d) + 9), Paint()..color = _soilLine..strokeWidth = 1);
    }
    final hole = Rect.fromLTRB(holeL, y(0), holeR, y(s.bottomDepthM));
    canvas.drawRect(hole, Paint()..color = _slurry);

    // --- concrete ------------------------------------------------------------
    final cTop = y(concreteNowM.clamp(0.0, s.bottomDepthM));
    if (concreteNowM < s.bottomDepthM - 0.01) {
      final wave = Path()..moveTo(holeL, cTop);
      for (var x = holeL; x <= holeR; x += 3) {
        final amp = live ? 2.2 : 0.8;
        wave.lineTo(x, cTop + math.sin((x - holeL) / holeW * 2 * math.pi * 1.5 + phase * 2 * math.pi) * amp);
      }
      wave
        ..lineTo(holeR, hole.bottom)
        ..lineTo(holeL, hole.bottom)
        ..close();
      canvas.drawPath(
        wave,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_concreteTop, _concrete])
              .createShader(Rect.fromLTRB(holeL, cTop, holeR, hole.bottom)),
      );
    }
    canvas.drawRect(hole, Paint()..color = colors.ink..style = PaintingStyle.stroke..strokeWidth = 2);

    // --- target of this truck --------------------------------------------------
    final target = s.concreteTargetM;
    if (target != null) _dashed(canvas, Offset(holeL + 2, y(target)), Offset(holeR - 2, y(target)), colors.ink.withValues(alpha: 0.55), 1.5);

    // --- cut-off and ground ---------------------------------------------------
    _dashed(canvas, Offset(holeL - 14, y(s.cutOffDepthM)), Offset(holeR + 14, y(s.cutOffDepthM)), colors.brand, 2);
    canvas.drawLine(Offset(holeL - 34, y(0)), Offset(holeR + 34, y(0)), Paint()..color = colors.ink..strokeWidth = 2);

    // --- tremie ---------------------------------------------------------------
    const pipeW = 12.0;
    final pipeL = cx - pipeW / 2;
    final total = s.tremieSegmentsM.fold(0.0, (a, b) => a + b);
    final tremieTop = tremieBottomM - total; // may be above ground (negative)
    final pipeTopY = math.max(14.0, y(tremieTop));
    final pipeBottomY = y(tremieBottomM);
    canvas.drawRect(Rect.fromLTRB(pipeL, pipeTopY, pipeL + pipeW, pipeBottomY), Paint()..color = const Color(0xFF3A3F48));
    if (live) {
      // Concrete moving down the pipe.
      final stripe = Paint()..color = _concreteTop.withValues(alpha: 0.85);
      const gap = 16.0;
      for (var yy = pipeTopY + (phase * gap) % gap; yy < pipeBottomY - 4; yy += gap) {
        canvas.drawRect(Rect.fromLTWH(pipeL + 3, yy, pipeW - 6, 6), stripe);
      }
    }
    // Joints, counted from the top segment down.
    var depth = tremieTop;
    for (final len in s.tremieSegmentsM) {
      depth += len;
      if (depth < tremieBottomM - 0.01 && y(depth) > pipeTopY) {
        canvas.drawLine(Offset(pipeL - 2, y(depth)), Offset(pipeL + pipeW + 2, y(depth)), Paint()..color = colors.surface..strokeWidth = 1.5);
      }
    }
    // Pointed tremie bottom.
    if (s.hasBottomPiece) {
      final tip = Path()
        ..moveTo(pipeL, pipeBottomY)
        ..lineTo(pipeL + pipeW, pipeBottomY)
        ..lineTo(cx, pipeBottomY + 9)
        ..close();
      canvas.drawPath(tip, Paint()..color = const Color(0xFF3A3F48));
    }
    // Hopper.
    final hopper = Path()
      ..moveTo(cx - 20, 2)
      ..lineTo(cx + 20, 2)
      ..lineTo(cx + 7, 16)
      ..lineTo(cx - 7, 16)
      ..close();
    canvas.drawPath(hopper, Paint()..color = colors.ink);

    // --- embedment bracket ----------------------------------------------------
    final emb = tremieBottomM - concreteNowM;
    const limits = EmbedmentLimits();
    final embColor = emb < limits.minimumM
        ? colors.badFg
        : emb > limits.maximumM
            ? colors.warnFg
            : colors.okFg;
    if (emb > 0) {
      final bx = holeR + 8;
      final p = Paint()
        ..color = embColor
        ..strokeWidth = 2.5;
      canvas.drawLine(Offset(bx, cTop), Offset(bx, pipeBottomY), p);
      canvas.drawLine(Offset(bx - 4, cTop), Offset(bx + 4, cTop), p);
      canvas.drawLine(Offset(bx - 4, pipeBottomY), Offset(bx + 4, pipeBottomY), p);
    }

    // --- depth scale ------------------------------------------------------------
    for (var d = 0.0; d <= s.bottomDepthM + 0.01; d += 5) {
      canvas.drawLine(Offset(left - 6, y(d)), Offset(left, y(d)), Paint()..color = colors.faint..strokeWidth = 1);
      _text(canvas, d == 0 ? '0' : '${d.toStringAsFixed(0)} m', Offset(0, y(d) - 7), 11, colors.muted, width: left - 8, align: TextAlign.right);
    }

    // --- labels (pushed apart so they never overlap) -----------------------------
    final labels = <_Label>[
      _Label(y(0), 'GS', 'muka tanah', colors.ink),
      _Label(y(s.cutOffDepthM), 'Cut-off', formatMeters(s.cutOffDepthM), colors.brand),
      if (target != null) _Label(y(target), 'Akhir TM ini ±', formatMeters(target), colors.ink),
      _Label(cTop, s.concreteMeasured ? 'Muka beton' : 'Muka beton ±', formatMeters(concreteNowM), colors.ink),
      if (emb > 0) _Label((cTop + pipeBottomY) / 2, 'Tertanam', formatMeters(emb), embColor),
      _Label(pipeBottomY, 'Ujung tremie', formatMeters(tremieBottomM), colors.muted),
    ]..sort((a, b) => a.y.compareTo(b.y));
    const minGap = 28.0;
    var lastY = -1000.0;
    for (final l in labels) {
      l.drawY = math.max(l.y, lastY + minGap);
      lastY = l.drawY;
    }
    // Pull back up if the stack ran off the bottom.
    final overflow = lastY + 24 - size.height;
    if (overflow > 0) {
      for (final l in labels.reversed) {
        l.drawY -= overflow;
      }
    }
    final lx = size.width - labelsW + 10;
    for (final l in labels) {
      canvas.drawLine(Offset(holeR + 16, l.y), Offset(lx - 4, l.drawY), Paint()..color = l.color.withValues(alpha: 0.35)..strokeWidth = 1);
      _text(canvas, l.title, Offset(lx, l.drawY - 8), 12, l.color, bold: true, width: labelsW - 10);
      _text(canvas, l.value, Offset(lx, l.drawY + 6), 11, colors.muted, width: labelsW - 10);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 9) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 5, len), paint);
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color,
      {bool bold = false, double width = 120, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'Montserrat', fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SectionPainter old) =>
      old.phase != phase ||
      old.concreteNowM != concreteNowM ||
      old.tremieBottomM != tremieBottomM ||
      old.live != live ||
      old.s != s ||
      old.colors != colors;
}

class _Label {
  _Label(this.y, this.title, this.value, this.color) : drawY = y;

  final double y;
  final String title;
  final String value;
  final Color color;
  double drawY;
}
