import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'daily_report.dart';

/// DAILY REPORT PICTURE — drawn straight onto a canvas, like the web.
///
/// Port of the web's `laporan-harian-gambar.ts`: same size (1200 wide, 2x),
/// same columns, same colours, same Barlow type. Daniel, 22 Nov 2026: the
/// web picture "sumpah bagus banget" — the phone sends the SAME picture, so
/// nobody in the group can tell where it was made.
///
/// Nothing here translates or calculates: every sentence comes through
/// [ReportTexts], every number from [DailyReport]. This file only puts
/// things in their place.

class ReportTexts {
  const ReportTexts({
    required this.title,
    required this.date,
    required this.project,
    required this.client,
    required this.drillTitle,
    required this.drillSummary,
    required this.drillEmpty,
    required this.drillColumns,
    required this.castTitle,
    required this.castSummary,
    required this.castEmpty,
    required this.castColumns,
    required this.status,
    required this.total,
    required this.truckCount,
    required this.footer,
  });

  final String title;
  final String date;
  final String project;
  final String? client;
  final String drillTitle;
  final String drillSummary;
  final String drillEmpty;
  final List<String> drillColumns;
  final String castTitle;
  final String castSummary;
  final String castEmpty;
  final List<String> castColumns;

  /// Text of the Status column per truck status.
  final Map<TruckStatus, String> status;
  final String total;
  final String truckCount;
  final String footer;
}

/// Number in the reader's language ("16,9" / "16.9").
typedef NumberFormatFn = String Function(double n, int maxDecimals);

const double pixelRatio = 2;
const double imageWidth = 1200;
const double _margin = 48;
const double tableWidth = imageWidth - _margin * 2;

const double _sectionTitleH = 44;
const double _headH = 50;
const double rowH = 34;
const double _emptyH = 46;
const double _totalH = 38;
const double _sectionGap = 36;
const double _pageHeadH = 8 + 40 + 104 + 20;
const double _footerH = 64;

class _C {
  static const gold = Color(0xFFBD925B);
  static const ink = Color(0xFF24211D);
  static const muted = Color(0xFF7A7268);
  static const line = Color(0xFFE9E3DA);
  static const lineStrong = Color(0xFFCFC6B8);
  static const head = Color(0xFF3B3328);
  static const total = Color(0xFFF3ECE2);
  static const stripe = Color(0xFFFAF7F2);
  static const paper = Color(0xFFFFFFFF);
  static const ok = Color(0xFF1E7B4F);
  static const pouring = Color(0xFFB4610E);
  static const onSite = Color(0xFF2E5E8C);
}

/// Status column colours: green done, orange pouring, blue just arrived.
const statusColors = {
  TruckStatus.done: _C.ok,
  TruckStatus.pouring: _C.pouring,
  TruckStatus.onSite: _C.onSite,
};

const _font = 'Barlow';
const _fontNarrow = 'BarlowCondensed';

enum _Align { left, right, center }

class _Col {
  const _Col(this.width, this.align);
  final double width;
  final _Align align;
}

/// No · Point · Operator · Start · End · Depth · Duration · Speed
const _drillColumns = [
  _Col(56, _Align.center),
  _Col(150, _Align.left),
  _Col(298, _Align.left),
  _Col(110, _Align.center),
  _Col(110, _Align.center),
  _Col(130, _Align.right),
  _Col(110, _Align.center),
  _Col(140, _Align.right),
];

/// No · Point · Supplier · Truck · Volume · Cumulative · Status · Slump ·
/// Start · End · Concrete level · Duration — Daniel's Excel order.
const _castColumns = [
  _Col(48, _Align.center),
  _Col(120, _Align.left),
  _Col(150, _Align.left),
  _Col(80, _Align.center),
  _Col(84, _Align.right),
  _Col(96, _Align.right),
  _Col(104, _Align.center),
  _Col(74, _Align.right),
  _Col(80, _Align.center),
  _Col(80, _Align.center),
  _Col(104, _Align.right),
  _Col(84, _Align.center),
];

double _sum(List<_Col> cols) => cols.fold(0.0, (s, c) => s + c.width);

/// Guarded by a test: the columns must add up to [tableWidth] exactly.
({double drill, double cast}) columnWidths() => (drill: _sum(_drillColumns), cast: _sum(_castColumns));

double imageHeight(DailyReport r) {
  double section(int rows) => _sectionTitleH + _headH + (rows > 0 ? rows * rowH + _totalH : _emptyH);
  return _pageHeadH + section(r.drilling.length) + _sectionGap + section(r.truckRows) + _footerH;
}

ui.Image? _logo;

/// The AKN logo, decoded once per app run.
Future<ui.Image?> _loadLogo() async {
  if (_logo != null) return _logo;
  try {
    final data = await rootBundle.load('assets/images/akn-logo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    _logo = (await codec.getNextFrame()).image;
  } catch (_) {
    // Without the logo the report is still whole.
  }
  return _logo;
}

/// The picture as PNG bytes.
Future<Uint8List> drawDailyReport(DailyReport r, ReportTexts t, NumberFormatFn fmt) async {
  final logo = await _loadLogo();
  final height = imageHeight(r);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(pixelRatio);
  final p = _Painter(c);

  c.drawRect(Rect.fromLTWH(0, 0, imageWidth, height), Paint()..color = _C.paper);
  c.drawRect(const Rect.fromLTWH(0, 0, imageWidth, 8), Paint()..color = _C.gold);

  var y = p.pageHead(t, logo);
  y = p.drillTable(y, r, t, fmt);
  y += _sectionGap;
  y = p.castTable(y, r, t, fmt);
  p.footer(y, height, t.footer);

  final img = await rec.endRecording().toImage((imageWidth * pixelRatio).round(), (height * pixelRatio).round());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (png == null) throw StateError('PNG encoding failed');
  return png.buffer.asUint8List();
}

class _Painter {
  _Painter(this.c);
  final Canvas c;

  Color _color = _C.ink;
  FontWeight _weight = FontWeight.w400;
  double _size = 15;
  bool _narrow = false;

  void font(FontWeight w, double size, {bool narrow = false}) {
    _weight = w;
    _size = size;
    _narrow = narrow;
  }

  void fill(Rect r, Color color) => c.drawRect(r, Paint()..color = color);

  TextPainter _tp(String s, {double? maxWidth, bool ellipsis = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: _narrow ? _fontNarrow : _font,
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
          fontWeight: _weight,
          fontSize: _size,
          color: _color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: ellipsis ? '…' : null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  double measure(String s) {
    final tp = _tp(s, ellipsis: false);
    final w = tp.width;
    tp.dispose();
    return w;
  }

  /// One line of text centred vertically on [y]; cut with "…" if too wide.
  void write(String s, double x, double y, double width, _Align align) {
    final tp = _tp(s, maxWidth: math.max(1, width));
    final dx = switch (align) {
      _Align.left => x,
      _Align.right => x + width - tp.width,
      _Align.center => x + (width - tp.width) / 2,
    };
    tp.paint(c, Offset(dx, y - tp.height / 2));
    tp.dispose();
  }

  /// Split by words into at most two lines (column headings).
  List<String> splitTwo(String s, double width) {
    if (measure(s) <= width) return [s];
    final words = s.split(' ');
    for (var i = words.length - 1; i > 0; i--) {
      final a = words.sublist(0, i).join(' ');
      if (measure(a) <= width) return [a, words.sublist(i).join(' ')];
    }
    return [s];
  }

  double pageHead(ReportTexts t, ui.Image? logo) {
    const top = 8.0 + 40;
    var x = _margin;
    if (logo != null) {
      c.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        const Rect.fromLTWH(_margin, top, 73, 72),
        Paint()..filterQuality = FilterQuality.high,
      );
      x = _margin + 73 + 22;
    }
    final leftWidth = imageWidth - _margin - x - 300;

    _color = _C.ink;
    font(FontWeight.w700, 34, narrow: true);
    write(t.title, x, top + 16, leftWidth, _Align.left);
    font(FontWeight.w600, 19);
    write(t.project, x, top + 50, leftWidth, _Align.left);
    if (t.client != null) {
      _color = _C.muted;
      font(FontWeight.w400, 15);
      write(t.client!, x, top + 76, leftWidth, _Align.left);
    }

    _color = _C.ink;
    font(FontWeight.w600, 22, narrow: true);
    write(t.date, imageWidth - _margin - 290, top + 16, 290, _Align.right);

    const lineY = top + 104;
    fill(const Rect.fromLTWH(_margin, lineY, tableWidth, 1), _C.lineStrong);
    return lineY + 20;
  }

  void sectionTitle(double y, String title, String summary) {
    _color = _C.ink;
    font(FontWeight.w700, 22, narrow: true);
    write(title, _margin, y + 16, tableWidth / 2, _Align.left);
    _color = _C.muted;
    font(FontWeight.w600, 15);
    write(summary, _margin + tableWidth / 2, y + 16, tableWidth / 2, _Align.right);
  }

  void tableHead(double y, List<_Col> cols, List<String> labels) {
    fill(Rect.fromLTWH(_margin, y, tableWidth, _headH), _C.head);
    _color = const Color(0xFFFFFFFF);
    font(FontWeight.w600, 13.5);
    var x = _margin;
    for (var i = 0; i < cols.length; i++) {
      final k = cols[i];
      final lines = splitTwo(i < labels.length ? labels[i] : '', k.width - 12);
      final mid = y + _headH / 2;
      for (var j = 0; j < lines.length; j++) {
        final dy = lines.length == 1 ? 0.0 : (j == 0 ? -8.0 : 8.0);
        write(lines[j], x + 6, mid + dy, k.width - 12, _Align.center);
      }
      x += k.width;
    }
  }

  /// Column lines and the outer frame, after the content. An EMPTY table
  /// gets no column lines: its sentence runs across the full width.
  void tableLines(double top, double bottom, List<_Col> cols, {bool empty = false}) {
    var x = _margin;
    for (var i = 0; i < cols.length - 1 && !empty; i++) {
      x += cols[i].width;
      fill(Rect.fromLTWH(x, top + _headH, 1, bottom - top - _headH), _C.line);
    }
    c.drawRect(
      Rect.fromLTWH(_margin + 0.5, top + 0.5, tableWidth - 1, bottom - top - 1),
      Paint()
        ..color = _C.lineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void cell(List<_Col> cols, int i, double y, double h, String? value) {
    var x = _margin;
    for (var k = 0; k < i; k++) {
      x += cols[k].width;
    }
    final k = cols[i];
    final empty = value == null || value.isEmpty;
    final keep = _color;
    if (empty) _color = _C.muted;
    write(empty ? '–' : value, x + 12, y + h / 2, k.width - 24, empty ? _Align.center : k.align);
    _color = keep;
  }

  double emptyRow(double y, String sentence) {
    _color = _C.muted;
    font(FontWeight.w400, 15);
    write(sentence, _margin + 16, y + _emptyH / 2, tableWidth - 32, _Align.center);
    return y + _emptyH;
  }

  double drillTable(double y0, DailyReport r, ReportTexts t, NumberFormatFn fmt) {
    sectionTitle(y0, t.drillTitle, t.drillSummary);
    final top = y0 + _sectionTitleH;
    tableHead(top, _drillColumns, t.drillColumns);
    var y = top + _headH;

    if (r.drilling.isEmpty) {
      y = emptyRow(y, t.drillEmpty);
    } else {
      for (var i = 0; i < r.drilling.length; i++) {
        final b = r.drilling[i];
        if (i.isOdd) fill(Rect.fromLTWH(_margin, y, tableWidth, rowH), _C.stripe);
        if (i > 0) fill(Rect.fromLTWH(_margin, y, tableWidth, 1), _C.line);
        _color = _C.ink;
        final values = [
          '${b.no}',
          b.point,
          b.operator,
          b.start,
          b.end,
          // A hole continued from an earlier day: "15 → 21", and the total
          // adds only the 6 (SP.B73, 23 Nov 2026).
          b.depthM == null
              ? null
              : (b.startDepthM ?? 0) > 0
                  ? '${fmt(b.startDepthM!, 1)} → ${fmt(b.depthM!, 1)}'
                  : fmt(b.depthM!, 1),
          durationText(b.minutes),
          b.speed == null ? null : fmt(b.speed!, 2),
        ];
        for (var k = 0; k < values.length; k++) {
          font(k == 1 ? FontWeight.w600 : FontWeight.w400, 15);
          cell(_drillColumns, k, y, rowH, values[k]);
        }
        y += rowH;
      }
      y = totalRow(y, _drillColumns, t.total, {5: fmt(r.totalDrillM, 1)});
    }
    tableLines(top, y, _drillColumns, empty: r.drilling.isEmpty);
    return y;
  }

  double castTable(double y0, DailyReport r, ReportTexts t, NumberFormatFn fmt) {
    sectionTitle(y0, t.castTitle, t.castSummary);
    final top = y0 + _sectionTitleH;
    tableHead(top, _castColumns, t.castColumns);
    var y = top + _headH;

    if (r.casting.isEmpty) {
      y = emptyRow(y, t.castEmpty);
    } else {
      for (var gi = 0; gi < r.casting.length; gi++) {
        final g = r.casting[gi];
        final groupH = g.trucks.length * rowH;
        if (gi.isOdd) fill(Rect.fromLTWH(_margin, y, tableWidth, groupH), _C.stripe);
        // Between piles the line is STRONG: readers look for the pile first.
        if (gi > 0) fill(Rect.fromLTWH(_margin, y, tableWidth, 1), _C.lineStrong);

        for (var ti = 0; ti < g.trucks.length; ti++) {
          final tr = g.trucks[ti];
          final yb = y + ti * rowH;
          if (ti > 0) {
            // Truck lines stop short of the pile's own columns (No, Point,
            // Supplier, Duration), so those read as one merged cell.
            final left = _margin + _castColumns[0].width + _castColumns[1].width + _castColumns[2].width;
            final right = _margin + tableWidth - _castColumns[11].width;
            fill(Rect.fromLTWH(left, yb, right - left, 1), _C.line);
          }
          _color = _C.ink;
          font(FontWeight.w400, 15);
          final values = <int, String?>{
            3: tr.truckNo,
            4: tr.volumeM3 == null ? null : fmt(tr.volumeM3!, 2),
            5: tr.cumulativeM3 == null ? null : fmt(tr.cumulativeM3!, 2),
            7: tr.slumpCm == null ? null : fmt(tr.slumpCm!, 1),
            8: tr.start,
            9: tr.end,
            10: tr.concreteLevelM == null ? null : fmt(tr.concreteLevelM!, 2),
          };
          values.forEach((k, v) => cell(_castColumns, k, yb, rowH, v));
          _color = statusColors[tr.status]!;
          font(FontWeight.w600, 15);
          cell(_castColumns, 6, yb, rowH, t.status[tr.status]);
        }

        _color = _C.ink;
        font(FontWeight.w400, 15);
        cell(_castColumns, 0, y, rowH, '${g.no}');
        font(FontWeight.w600, 15);
        cell(_castColumns, 1, y, rowH, g.point);
        font(FontWeight.w400, 15);
        cell(_castColumns, 2, y, rowH, g.supplier);
        cell(_castColumns, 11, y, rowH, durationText(g.minutes));
        y += groupH;
      }
      y = totalRow(y, _castColumns, t.total, {3: t.truckCount, 4: fmt(r.totalCastM3, 2)});
    }
    tableLines(top, y, _castColumns, empty: r.casting.isEmpty);
    return y;
  }

  double totalRow(double y, List<_Col> cols, String label, Map<int, String> values) {
    fill(Rect.fromLTWH(_margin, y, tableWidth, _totalH), _C.total);
    fill(Rect.fromLTWH(_margin, y, tableWidth, 1), _C.lineStrong);
    _color = _C.ink;
    font(FontWeight.w700, 15);
    // The label sits in the Point column — not across the No column line.
    cell(cols, 1, y, _totalH, label);
    values.forEach((i, v) => cell(cols, i, y, _totalH, v));
    return y + _totalH;
  }

  void footer(double y, double height, String text) {
    _color = _C.muted;
    font(FontWeight.w400, 12.5);
    write(text, _margin, math.min(y + 34, height - 24), tableWidth, _Align.left);
  }
}
