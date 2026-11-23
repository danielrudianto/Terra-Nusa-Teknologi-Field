import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/reports/daily_report.dart';
import 'package:terrabot_field/features/reports/daily_report_image.dart';

/// Same rules as the web's `laporan-harian.helper.spec.ts`: the picture
/// from a phone and from the office must not disagree.
Map<String, Object?> truck(int? seq, {String no = '823', Object? vol = '6.00', String? start, String? end, Object? level}) => {
      'seq': seq,
      'truckNo': no,
      'supplierName': 'Adhimix',
      'volumeM3': vol,
      'slumpCm': '18.0',
      'startAt': start,
      'endAt': end,
      'concreteDepthAfterM': level,
    };

Map<String, Object?> report({List<Map<String, Object?>> drilling = const [], List<Map<String, Object?>> casting = const []}) => {
      'date': '2026-11-22',
      'project': {'id': 64, 'code': 'R501', 'name': 'Secant Pile R501', 'clientName': 'PT Dwijaya Putra'},
      'drilling': drilling,
      'casting': casting,
    };

Map<String, Object?> cast(String code, List<Map<String, Object?>> trucks) =>
    {'uuid': code, 'status': 'selesai', 'pilePointCode': code, 'diameterMm': 800, 'trucks': trucks};

void main() {
  test('truck status read from its times', () {
    expect(truckStatus(startAt: null, endAt: null), TruckStatus.onSite);
    expect(truckStatus(startAt: '2026-11-22T10:00:00', endAt: null), TruckStatus.pouring);
    expect(truckStatus(startAt: '2026-11-22T10:00:00', endAt: '2026-11-22T10:05:00'), TruckStatus.done);
  });

  test('clock is read from the text, not through the phone time zone', () {
    expect(clock('2026-11-22T08:03:00'), '08:03');
    expect(clock('2026-11-22 14:24:10'), '14:24');
    expect(clock(null), isNull);
  });

  test('duration like the Excel sheet', () {
    expect(durationText(158), '02:38');
    expect(durationText(null), isNull);
  });

  test('drilling: points still being drilled are left out; speed against duration', () {
    final r = dailyReport(report(drilling: [
      {'pilePointCode': 'SP.B69', 'pointStatus': 'sudah_bor', 'depthM': '29.4', 'startAt': '2026-11-22T08:03:00', 'endAt': '2026-11-22T10:41:00', 'operatorName': 'Anura'},
      {'pilePointCode': 'SP.B71', 'pointStatus': 'sedang_bor', 'depthM': '12', 'startAt': '2026-11-22T11:00:00', 'endAt': null},
    ]));
    expect(r.drilling.map((b) => b.point), ['SP.B69']);
    expect(r.drilling.first.minutes, 158);
    expect(r.drilling.first.speed, closeTo(29.4 / 158, 1e-9));
    expect(r.totalDrillM, closeTo(29.4, 1e-9));
  });

  test('drilling: a hole continued from yesterday adds only today\'s metres', () {
    // SP.B73, 23 Nov 2026: 15 m on the 22nd, 21 m on the 23rd.
    final r = dailyReport(report(drilling: [
      {'pilePointCode': 'SP.B73', 'pointStatus': 'belum_bor', 'depthM': '21', 'depthStartM': '15', 'meters': '6',
       'startAt': '2026-11-23T07:56:00', 'endAt': '2026-11-23T08:29:00', 'operatorName': 'Anura'},
      {'pilePointCode': 'SP.B75', 'pointStatus': 'sudah_bor', 'depthM': '10', 'meters': '10',
       'startAt': '2026-11-23T09:00:00', 'endAt': '2026-11-23T10:00:00'},
    ]));
    final b = r.drilling.first;
    expect(b.depthM, 21);
    expect(b.startDepthM, 15);
    expect(b.metersM, 6);
    expect(b.speed, closeTo(6 / 33, 1e-9));
    expect(r.totalDrillM, closeTo(16, 1e-9));
  });

  test('casting: totals count FINISHED trucks only; gate trucks go last as on site', () {
    final r = dailyReport(report(casting: [
      cast('PP.B94', [
        truck(null, no: '930'),
        truck(1, no: '818', start: '2026-11-22T16:30:00', end: '2026-11-22T16:33:00', level: '21.6'),
        truck(2, no: '811', start: '2026-11-22T16:40:00'),
      ]),
    ]));
    final g = r.casting.single;
    expect(g.trucks.map((t) => t.truckNo), ['818', '811', '930']);
    expect(g.trucks.map((t) => t.status), [TruckStatus.done, TruckStatus.pouring, TruckStatus.onSite]);
    expect(r.finishedTrucks, 1);
    expect(r.totalCastM3, 6);
    expect(r.truckRows, 3);
    expect(g.trucks.first.concreteLevelM, 21.6);
  });

  test('cumulative stops at the first truck without a volume', () {
    final g = dailyReport(report(casting: [
      cast('A', [truck(1, vol: '6'), truck(2, vol: null), truck(3, vol: '5')]),
    ])).casting.single;
    expect(g.trucks.map((t) => t.cumulativeM3), [6, null, null]);
  });

  test('suppliers distinct in truck order; empty report', () {
    final g = dailyReport(report(casting: [cast('A', [truck(1), truck(2)])])).casting.single;
    expect(g.supplier, 'Adhimix');
    expect(dailyReport(report()).isEmpty, isTrue);
    expect(dailyReport(report()).fileName, 'Laporan-Harian_R501_2026-11-22.png');
  });

  test('picture columns add up to the table width exactly', () {
    final w = columnWidths();
    expect(w.drill, tableWidth);
    expect(w.cast, tableWidth);
  });

  test('each truck row adds one row height to the picture', () {
    final one = dailyReport(report(casting: [cast('A', [truck(1)])]));
    final two = dailyReport(report(casting: [cast('A', [truck(1), truck(2)])]));
    expect(imageHeight(two) - imageHeight(one), rowH);
  });
}
