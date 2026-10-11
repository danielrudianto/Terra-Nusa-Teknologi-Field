import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/pauses.dart';

void main() {
  final truck = {'seq': 1, 'startAt': '2026-10-08T08:00:00+07:00', 'endAt': null};
  final pauses = <Map<String, Object?>>[
    {'truckSeq': 1, 'startAt': '2026-10-08T08:05:00+07:00', 'endAt': '2026-10-08T08:09:00+07:00', 'reason': 'cabut_tremie'},
    {'truckSeq': 2, 'startAt': '2026-10-08T08:06:00+07:00', 'endAt': '2026-10-08T08:30:00+07:00', 'reason': 'tunggu_tm'},
    {'truckSeq': 1, 'startAt': '2026-10-08T08:15:00+07:00', 'endAt': null, 'reason': 'tunggu_tm'},
  ];
  final now = DateTime.parse('2026-10-08T08:20:00+07:00');

  test('only this truck\'s pauses count, an open one up to now', () {
    expect(pausedTime(pauses, 1, now), const Duration(minutes: 9));
  });

  test('pouring time leaves the pauses out', () {
    expect(pouringTime(truck, pauses, now), const Duration(minutes: 11));
  });

  test('open pause is found', () {
    expect(openPause(pauses, 1)?['reason'], 'tunggu_tm');
    expect(openPause(pauses, 2), isNull);
  });

  test('a finished truck counts an open pause only up to its end', () {
    final done = {...truck, 'endAt': '2026-10-08T08:17:00+07:00'};
    // 17 min − 4 min − 2 min (08:15 → 08:17).
    expect(pouringTime(done, pauses, now), const Duration(minutes: 11));
  });

  test('not started = no pouring time', () {
    expect(pouringTime({'seq': 3, 'startAt': null}, pauses, now), isNull);
  });
}
