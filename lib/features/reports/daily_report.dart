/// DAILY FIELD REPORT — from the server's answer to the rows that are drawn.
///
/// Port of the web's `helpers/laporan-harian.helper.ts`. Asked by Daniel,
/// 22 Nov 2026: "Laporan harian kan udah bagus. Pengen bisa dilakukan di hp
/// juga". The rules are the SAME as the web, so the picture sent to the
/// group from a phone and from the office cannot disagree:
///
///   * every truck the gate has recorded is drawn, with its status: on site
///     (no start yet), pouring (started, not finished), done. Gate tickets
///     not yet recorded at the hole arrive from the SERVER as trucks with no
///     `seq` and no times;
///   * totals and the summary count FINISHED trucks only — concrete still in
///     a truck has not been cast;
///   * points still being drilled are not drawn: their depth and finish
///     time are not final.
///
/// All pure functions — a mistake here throws nothing, it only puts a wrong
/// number on the picture that goes to the group.
library;

/// Status of one truck, read from its times.
enum TruckStatus { onSite, pouring, done }

TruckStatus truckStatus({required String? startAt, required String? endAt}) {
  if (endAt != null && endAt.isNotEmpty) return TruckStatus.done;
  if (startAt != null && startAt.isNotEmpty) return TruckStatus.pouring;
  return TruckStatus.onSite;
}

class DrillRow {
  const DrillRow({
    required this.no,
    required this.point,
    required this.operator,
    required this.start,
    required this.end,
    required this.depthM,
    required this.minutes,
    required this.speed,
    this.startDepthM,
    this.metersM,
  });

  final int no;
  final String point;
  final String? operator;

  /// "HH:mm"; null when not recorded (point marked drilled without a log).
  final String? start;
  final String? end;
  final double? depthM;

  /// Where the day started on a hole continued from an earlier day (SP.B73:
  /// 15 m), null or 0 for a hole begun that day.
  final double? startDepthM;

  /// Metres drilled THAT DAY: [depthM] minus [startDepthM]. The total adds
  /// these, so a continued hole is not counted twice.
  final double? metersM;

  /// Minutes from the first reading to the last — same as the Excel sheet.
  final int? minutes;

  /// Metres per minute, against [minutes].
  final double? speed;
}

class TruckRow {
  const TruckRow({
    required this.truckNo,
    required this.status,
    required this.volumeM3,
    required this.cumulativeM3,
    required this.slumpCm,
    required this.start,
    required this.end,
    required this.concreteLevelM,
  });

  final String? truckNo;
  final TruckStatus status;
  final double? volumeM3;

  /// Running total up to this truck. Null from the first truck whose volume
  /// is missing: summing on while skipping blanks gives a total that is too
  /// small with nothing on it to say so.
  final double? cumulativeM3;
  final double? slumpCm;
  final String? start;
  final String? end;

  /// Concrete level below ground after this truck.
  final double? concreteLevelM;
}

class CastGroup {
  const CastGroup({
    required this.no,
    required this.point,
    required this.supplier,
    required this.minutes,
    required this.trucks,
  });

  final int no;
  final String point;

  /// Distinct supplier names, in truck order, joined by commas.
  final String? supplier;

  /// Minutes from the first truck's start to the last truck's end.
  final int? minutes;
  final List<TruckRow> trucks;
}

class DailyReport {
  const DailyReport({
    required this.date,
    required this.projectCode,
    required this.projectName,
    required this.clientName,
    required this.drilling,
    required this.casting,
    required this.totalDrillM,
    required this.totalCastM3,
    required this.finishedTrucks,
    required this.truckRows,
  });

  final String date;
  final String projectCode;
  final String projectName;
  final String? clientName;
  final List<DrillRow> drilling;
  final List<CastGroup> casting;
  final double totalDrillM;

  /// Volume of FINISHED trucks only.
  final double totalCastM3;

  /// Number of FINISHED trucks only.
  final int finishedTrucks;

  /// Truck rows drawn, including on-site and pouring ones.
  final int truckRows;

  bool get isEmpty => drilling.isEmpty && casting.isEmpty;

  /// `Laporan-Harian_R501_2026-11-21.png` — same name as the web download.
  String get fileName => 'Laporan-Harian_${projectCode}_$date.png';
}

double? number(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

String? _text(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// "HH:mm" read from the TEXT of the server time — not through the phone's
/// time zone: the server sends field (WIB) times without a zone.
String? clock(Object? v) {
  final s = _text(v);
  if (s == null) return null;
  final m = RegExp(r'T(\d{2}):(\d{2})').firstMatch(s) ?? RegExp(r'\s(\d{2}):(\d{2})').firstMatch(s);
  return m == null ? null : '${m.group(1)}:${m.group(2)}';
}

DateTime? _instant(Object? v) {
  final s = _text(v);
  return s == null ? null : DateTime.tryParse(s);
}

/// Minutes between two times; null when one is missing or reversed.
int? minutesBetween(Object? from, Object? to) {
  final a = _instant(from);
  final b = _instant(to);
  if (a == null || b == null || b.isBefore(a)) return null;
  return (b.difference(a).inSeconds / 60).round();
}

/// "01:16" — hours and minutes, like the duration column of the Excel sheet.
String? durationText(int? minutes) {
  if (minutes == null) return null;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int _byTime(Object? a, Object? b) {
  final x = _instant(a);
  final y = _instant(b);
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y);
}

List<Map<String, Object?>> _maps(Object? v) => [for (final x in (v as List?) ?? const []) (x as Map).cast<String, Object?>()];

List<DrillRow> drillRows(List<Map<String, Object?>> list) {
  final rows = list.where((b) => b['pointStatus'] != 'sedang_bor').toList()
    ..sort((a, b) {
      final c = _byTime(a['startAt'] ?? a['endAt'], b['startAt'] ?? b['endAt']);
      return c != 0 ? c : '${a['pilePointCode']}'.compareTo('${b['pilePointCode']}');
    });
  return [
    for (var i = 0; i < rows.length; i++)
      () {
        final b = rows[i];
        final depth = number(b['depthM']);
        final from = number(b['depthStartM']);
        // Old server without `meters`: the whole depth, as before.
        final meters = number(b['meters']) ?? depth;
        final minutes = minutesBetween(b['startAt'], b['endAt']);
        final op = _text(b['operatorName'])?.trim();
        return DrillRow(
          no: i + 1,
          point: '${b['pilePointCode']}',
          operator: op == null || op.isEmpty ? null : op,
          start: clock(b['startAt']),
          end: clock(b['endAt']),
          depthM: depth,
          minutes: minutes,
          startDepthM: from,
          metersM: meters,
          // Against the metres drilled in that time, not the hole's depth.
          speed: meters != null && minutes != null && minutes > 0 ? meters / minutes : null,
        );
      }(),
  ];
}

List<CastGroup> castGroups(List<Map<String, Object?>> list) {
  const last = 1 << 30;
  final groups = [
    for (final c in list)
      (
        c: c,
        trucks: _maps(c['trucks'])
          // Gate trucks (no seq) go under the ones recorded at the hole:
          // they arrived last.
          ..sort((a, b) => (toInt(a['seq']) ?? last).compareTo(toInt(b['seq']) ?? last)),
      ),
  ].where((g) => g.trucks.isNotEmpty).toList()
    ..sort((a, b) {
      final x = _byTime(a.trucks.first['startAt'] ?? a.trucks.first['endAt'], b.trucks.first['startAt'] ?? b.trucks.first['endAt']);
      return x != 0 ? x : '${a.c['pilePointCode']}'.compareTo('${b.c['pilePointCode']}');
    });

  return [
    for (var i = 0; i < groups.length; i++)
      () {
        final g = groups[i];
        double? running = 0;
        final rows = <TruckRow>[];
        for (final t in g.trucks) {
          final v = number(t['volumeM3']);
          running = running == null || v == null ? null : running + v;
          final no = _text(t['truckNo'])?.trim();
          rows.add(
            TruckRow(
              truckNo: no == null || no.isEmpty ? null : no,
              status: truckStatus(startAt: _text(t['startAt']), endAt: _text(t['endAt'])),
              volumeM3: v,
              cumulativeM3: running,
              slumpCm: number(t['slumpCm']),
              start: clock(t['startAt']),
              end: clock(t['endAt']),
              concreteLevelM: number(t['concreteDepthAfterM']),
            ),
          );
        }

        final names = <String>[];
        for (final t in g.trucks) {
          final n = _text(t['supplierName'])?.trim();
          if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
        }
        final starts = [for (final t in g.trucks) if (_text(t['startAt']) != null) t['startAt']]..sort(_byTime);
        final ends = [for (final t in g.trucks) if (_text(t['endAt']) != null) t['endAt']]..sort(_byTime);

        return CastGroup(
          no: i + 1,
          point: '${g.c['pilePointCode']}',
          supplier: names.isEmpty ? null : names.join(', '),
          minutes: minutesBetween(starts.isEmpty ? null : starts.first, ends.isEmpty ? null : ends.last),
          trucks: rows,
        );
      }(),
  ];
}

int? toInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

/// The whole report from `GET /field/reports/daily`.
DailyReport dailyReport(Map<String, Object?> json) {
  final project = ((json['project'] as Map?) ?? const {}).cast<String, Object?>();
  final drilling = drillRows(_maps(json['drilling']));
  final casting = castGroups(_maps(json['casting']));
  final all = [for (final g in casting) ...g.trucks];
  final done = all.where((t) => t.status == TruckStatus.done).toList();
  final client = _text(project['clientName'])?.trim();
  return DailyReport(
    date: '${json['date']}',
    projectCode: '${project['code'] ?? ''}',
    projectName: '${project['name'] ?? ''}',
    clientName: client == null || client.isEmpty ? null : client,
    drilling: drilling,
    casting: casting,
    totalDrillM: drilling.fold(0.0, (s, b) => s + (b.metersM ?? b.depthM ?? 0)),
    totalCastM3: done.fold(0.0, (s, t) => s + (t.volumeM3 ?? 0)),
    finishedTrucks: done.length,
    truckRows: all.length,
  );
}
