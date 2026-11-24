import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_snack.dart';

/// CONCRETE PROFILE — necking and bulking per truck, from sounding and m³.
///
/// The same calculation as TerraBot Engineering's Live page
/// (`profil-beton.helper.ts`), brought to the phone so it can be copied and
/// shared from the field (Daniel, 24 Nov 2026: "untuk laporan bulking &
/// necking pengen bisa di copy dan share dari hp juga dong").
///
/// One truck fills the hole from the concrete level BEFORE it to the level
/// AFTER it. Its volume over that height gives the average cross-section:
///
///     ratio        = volume / (π/4 · D² · height)
///     effective Ø  = D · √ratio
///
/// Below 1 = less concrete than the design hole (necking); above 1 = more
/// (bulking). It is an AVERAGE over a stretch of a few metres, not the shape
/// of the wall — so stretches shorter than [minHeightM] are not judged.

/// Volume more than this below design = necking.
const neckingLimit = 0.05;

/// Volume more than this above design = bulking.
const bulkingLimit = 0.10;

/// Stretches shorter than this are not judged: the sounding decides too much.
const minHeightM = 0.5;

enum SegmentKind { necking, bulking, fits, short }

class ConcreteSegment {
  const ConcreteSegment({
    required this.seq,
    required this.topM,
    required this.bottomM,
    required this.volumeM3,
    required this.ratio,
    required this.diameterM,
    required this.kind,
  });

  final int seq;

  /// Depth from GS, m. [topM] < [bottomM].
  final double topM;
  final double bottomM;
  final double volumeM3;

  /// Actual / design volume of this stretch; null when it is too short.
  final double? ratio;

  /// Effective diameter, m; null when the stretch is too short.
  final double? diameterM;
  final SegmentKind kind;
}

double? _num(Object? v) => v == null || '$v'.isEmpty ? null : double.tryParse('$v');

/// The stretches whose both ends are KNOWN, bottom to top. A truck without
/// a sounding after it (still pouring, or never measured) has no top, so it
/// makes no stretch.
List<ConcreteSegment> concreteSegments(List<Map<String, Object?>> trucks, Object? diameterMm, double bottomM) {
  final d = _num(diameterMm);
  if (d == null || d <= 0) return const [];
  final dM = d / 1000;
  final area = math.pi / 4 * dM * dM;
  final sorted = [
    for (final t in trucks)
      if (t['isDelete'] != true && t['isDelete'] != 1) t,
  ]..sort((a, b) => (_num(a['seq']) ?? 0).compareTo(_num(b['seq']) ?? 0));

  final out = <ConcreteSegment>[];
  double? lastLevel;
  for (final t in sorted) {
    final vol = _num(t['volumeM3']);
    final after = _num(t['concreteDepthAfterM']);
    final before = _num(t['concreteDepthBeforeM']) ?? lastLevel ?? bottomM;
    if (after != null) lastLevel = after;
    if (vol == null || vol <= 0 || after == null) continue;
    final bottom = math.min(before, bottomM);
    final top = math.max(0.0, after);
    final height = bottom - top;
    if (height <= 0) continue;
    final seq = (_num(t['seq']) ?? 0).toInt();
    if (height < minHeightM) {
      out.add(ConcreteSegment(
        seq: seq, topM: top, bottomM: bottom, volumeM3: vol, ratio: null, diameterM: null, kind: SegmentKind.short,
      ));
      continue;
    }
    final ratio = vol / (area * height);
    out.add(ConcreteSegment(
      seq: seq,
      topM: top,
      bottomM: bottom,
      volumeM3: vol,
      ratio: ratio,
      diameterM: dM * math.sqrt(ratio),
      kind: ratio < 1 - neckingLimit
          ? SegmentKind.necking
          : ratio > 1 + bulkingLimit
              ? SegmentKind.bulking
              : SegmentKind.fits,
    ));
  }
  return out;
}

String _pct(double ratio) {
  final p = (ratio - 1).abs() * 100;
  return '${p.toStringAsFixed(p < 10 ? 1 : 0).replaceAll('.', ',')}%';
}

String _signedPct(double ratio) => '${ratio >= 1 ? '+' : '−'}${_pct(ratio)}';

String _dia(double m) => 'Ø ${m.toStringAsFixed(2).replaceAll('.', ',')} m';

/// The card on the Watch screen: the picture, one line per truck, and the
/// Copy (text) / Share (picture + text) buttons.
class ConcreteProfileCard extends StatefulWidget {
  const ConcreteProfileCard({
    super.key,
    required this.segments,
    required this.bottomM,
    required this.cutOffM,
    required this.diameterMm,
    required this.code,
  });

  final List<ConcreteSegment> segments;
  final double bottomM;
  final double cutOffM;
  final Object? diameterMm;
  final String code;

  @override
  State<ConcreteProfileCard> createState() => _ConcreteProfileCardState();
}

class _ConcreteProfileCardState extends State<ConcreteProfileCard> {
  final _picture = GlobalKey();
  bool _sharing = false;

  String _label(BuildContext context, ConcreteSegment s) {
    final l = t(context);
    return switch (s.kind) {
      SegmentKind.necking => l.profileNecking(_pct(s.ratio!)),
      SegmentKind.bulking => l.profileBulking,
      SegmentKind.fits => l.profileFits(_signedPct(s.ratio!)),
      SegmentKind.short => l.profileShort,
    };
  }

  /// The WhatsApp text: one line per truck, then the count.
  String _report(BuildContext context) {
    final l = t(context);
    final d = _num(widget.diameterMm);
    final b = StringBuffer()
      ..writeln(l.profileReportTitle(widget.code))
      ..writeln(l.profileReportDesign(
        d == null ? '–' : _dia(d / 1000),
        formatMeters(widget.bottomM),
      ));
    for (final s in widget.segments) {
      final depth = '${s.bottomM.toStringAsFixed(2).replaceAll('.', ',')} → ${formatMeters(s.topM)}';
      b.writeln(
        'TM #${s.seq}: $depth, ${formatVolume(s.volumeM3)}'
        '${s.diameterM == null ? '' : ', ${_dia(s.diameterM!)}'} — ${_label(context, s)}',
      );
    }
    int n(SegmentKind k) => widget.segments.where((s) => s.kind == k).length;
    b.write(l.profileReportCount('${n(SegmentKind.necking)}', '${n(SegmentKind.bulking)}', '${n(SegmentKind.fits)}'));
    return b.toString().replaceAll(' ', ' ');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report(context)));
    if (mounted) showSnack(context, t(context).profileCopied, icon: Icons.content_copy);
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final text = _report(context);
    XFile? file;
    try {
      final boundary = _picture.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png != null) {
          final dir = await getTemporaryDirectory();
          final f = File('${dir.path}/profil-beton-${widget.code.replaceAll(RegExp(r'[^A-Za-z0-9.-]'), '_')}.png');
          await f.writeAsBytes(png.buffer.asUint8List());
          file = XFile(f.path, mimeType: 'image/png');
        }
      }
    } catch (_) {
      // No picture: the text alone still goes.
    }
    if (!mounted) return;
    setState(() => _sharing = false);
    await SharePlus.instance.share(ShareParams(text: text, files: file == null ? null : [file]));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final judged = widget.segments.where((s) => s.ratio != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.profileTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: w.ink)),
        const SizedBox(height: 8),
        if (judged == 0)
          Text(l.profileNone, style: TextStyle(color: w.muted, height: 1.4))
        else ...[
          RepaintBoundary(
            key: _picture,
            child: ColoredBox(
              color: w.surface,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${l.profileTitle} · ${widget.code}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: w.ink),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 380,
                      child: CustomPaint(
                        painter: _ProfilePainter(
                          segments: widget.segments,
                          bottomM: widget.bottomM,
                          cutOffM: widget.cutOffM,
                          labelOf: (s) => _label(context, s),
                          colors: w,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(l.profileHow, style: TextStyle(color: w.muted, fontSize: 11, height: 1.35)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final s in widget.segments) _row(context, s),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: Text(l.profileCopy),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.share, size: 18),
                  label: Text(l.profileShare),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, ConcreteSegment s) {
    final w = context.colors;
    final color = switch (s.kind) {
      SegmentKind.necking => w.badFg,
      SegmentKind.bulking => w.warnFg,
      SegmentKind.fits => w.okFg,
      SegmentKind.short => w.muted,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('TM #${s.seq}', style: TextStyle(fontWeight: FontWeight.w700, color: w.ink))),
          Expanded(
            child: Text(
              '${s.bottomM.toStringAsFixed(2).replaceAll('.', ',')} → ${formatMeters(s.topM)}'
              '${s.diameterM == null ? '' : '  ${_dia(s.diameterM!)}'}',
              style: TextStyle(color: w.muted, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Text(_label(context, s), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.segments,
    required this.bottomM,
    required this.cutOffM,
    required this.labelOf,
    required this.colors,
  });

  final List<ConcreteSegment> segments;
  final double bottomM;
  final double cutOffM;
  final String Function(ConcreteSegment) labelOf;
  final TerraColors colors;

  void _text(Canvas c, String s, Offset at, {Color? color, double size = 11, FontWeight? weight, bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color ?? colors.muted, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(right ? at.dx - tp.width : at.dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    const top = 14.0;
    const left = 34.0;
    final labelW = math.min(150.0, size.width * 0.42);
    final cx = left + (size.width - left - labelW) / 2;
    const half = 26.0;
    final maxM = bottomM + 0.8;
    double y(double d) => top + d / maxM * (size.height - top - 8);

    // Soil, then the design hole.
    c.drawRect(
      Rect.fromLTRB(cx - half - 30, y(0), cx + half + 30, size.height),
      Paint()..color = colors.line.withValues(alpha: 0.6),
    );
    c.drawRect(Rect.fromLTRB(cx - half, y(0), cx + half, y(bottomM)), Paint()..color = colors.surface);

    // Depth scale every 5 m.
    for (var d = 0.0; d <= bottomM + 0.01; d += 5) {
      _text(c, d == 0 ? '0' : '${d.toStringAsFixed(0)} m', Offset(left - 6, y(d)), right: true, size: 10);
      c.drawLine(Offset(left - 2, y(d)), Offset(left + 2, y(d)), Paint()..color = colors.muted);
    }

    // Concrete per truck, its width scaled (×2) so 10% can be seen at all.
    final concrete = Paint()..color = colors.muted.withValues(alpha: 0.45);
    var widest = cx + half;
    final rects = <(ConcreteSegment, Rect)>[];
    for (final s in segments) {
      final f = s.ratio == null ? 1.0 : (1 + 2 * (math.sqrt(s.ratio!) - 1)).clamp(0.45, 1.6);
      final r = Rect.fromLTRB(cx - half * f, y(s.topM), cx + half * f, y(s.bottomM));
      c.drawRect(r, concrete);
      c.drawLine(r.topLeft, r.topRight, Paint()..color = colors.surface..strokeWidth = 1);
      widest = math.max(widest, r.right);
      rects.add((s, r));
    }

    // Design hole, dashed over the concrete.
    final dash = Paint()
      ..color = colors.ink.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final x in [cx - half, cx + half]) {
      for (var yy = y(0); yy < y(bottomM); yy += 6) {
        c.drawLine(Offset(x, yy), Offset(x, math.min(yy + 3, y(bottomM))), dash);
      }
    }

    // GS and cut-off.
    c.drawLine(Offset(cx - half - 30, y(0)), Offset(cx + half + 30, y(0)), Paint()..color = colors.ink..strokeWidth = 1.5);
    c.drawLine(
      Offset(cx - half - 10, y(cutOffM)),
      Offset(cx + half + 10, y(cutOffM)),
      Paint()
        ..color = colors.brand
        ..strokeWidth = 1.5,
    );

    // Brackets and labels, pushed apart so short stretches do not overlap.
    final xb = math.min(widest + 8, size.width - labelW - 4);
    final xl = size.width - labelW + 6;
    var lastY = -1e9;
    for (final (s, r) in rects) {
      if (s.ratio == null) continue;
      final color = switch (s.kind) {
        SegmentKind.necking => colors.badFg,
        SegmentKind.bulking => colors.warnFg,
        _ => colors.okFg,
      };
      final p = Paint()
        ..color = color
        ..strokeWidth = 2;
      c.drawLine(Offset(xb, r.top + 1), Offset(xb, r.bottom - 1), p);
      c.drawLine(Offset(xb - 4, r.top + 1), Offset(xb, r.top + 1), p);
      c.drawLine(Offset(xb - 4, r.bottom - 1), Offset(xb, r.bottom - 1), p);
      // Effective walls in the bracket colour.
      c.drawLine(r.topLeft, r.bottomLeft, p..strokeWidth = 1.5);
      c.drawLine(r.topRight, r.bottomRight, p);
      final ly = math.max(r.center.dy, lastY + 26);
      lastY = ly;
      c.drawLine(Offset(xb, r.center.dy), Offset(xl - 3, ly), Paint()..color = color.withValues(alpha: 0.5));
      _text(c, labelOf(s), Offset(xl, ly - 6), color: color, weight: FontWeight.w700);
      _text(c, '${_dia(s.diameterM!)} · TM #${s.seq}', Offset(xl, ly + 7), size: 10);
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.segments != segments || old.bottomM != bottomM;
}
