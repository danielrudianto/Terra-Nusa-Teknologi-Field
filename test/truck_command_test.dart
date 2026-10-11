import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/pauses.dart';
import 'package:terrabot_field/features/casting/calc/truck_command.dart';

/// The offset in the fixtures is +07:00; the phone running the test may be
/// anywhere, so compare INSTANTS, never strings.
void expectSameMoment(Object? iso, DateTime expected) {
  expect(DateTime.parse('$iso').isAtSameMomentAs(expected), isTrue, reason: 'expected $expected, got $iso');
}

Map<String, Object?> truckOf(Map<String, Object?> body) =>
    ((body['trucks'] as List).first as Map).cast<String, Object?>();

/// Stored pauses of a body, read the way the screen reads them.
List<Map<String, Object?>> storedPauses(Map<String, Object?> body) =>
    [for (final p in (body['pauses'] as List? ?? const [])) (p as Map).cast<String, Object?>()];

Map<String, Object?> castingBody({
  String status = 'berjalan',
  Object? soundingAfter,
  List<Object?> pauses = const [],
  bool running = true,
  bool finishedTruck = false,
}) =>
    {
      'status': status,
      'tremie': <Object?>[],
      'trucks': <Object?>[
        if (finishedTruck)
          <String, Object?>{
            'uuid': 'tm-0',
            'seq': 1,
            'startAt': '2026-10-08T07:00:00+07:00',
            'endAt': '2026-10-08T07:30:00+07:00',
            'concreteDepthAfterM': '11.00',
            'volumeM3': '7.00',
          },
        <String, Object?>{
          'uuid': finishedTruck ? 'tm-1' : 'tm-0',
          'seq': finishedTruck ? 2 : 1,
          'startAt': running ? '2026-10-08T08:00:00+07:00' : null,
          'endAt': null,
          'concreteDepthBeforeM': '12.00',
          'concreteDepthAfterM': soundingAfter,
          'volumeM3': '7.00',
        },
      ],
      'pauses': pauses,
    };

void main() {
  final at = DateTime.parse('2026-10-08T08:20:00+07:00');

  group('finish', () {
    test('stops the pour and reports the sounding is still missing', () {
      final body = castingBody();
      final r = applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expect(r.applied, isTrue);
      expect(r.seq, 1);
      expect(r.needsSounding, isTrue);
      expectSameMoment(truckOf(body)['endAt'], at);
    });

    test('does not ask for a sounding that is already there', () {
      final body = castingBody(soundingAfter: '10.50');
      final r = applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expect(r.needsSounding, isFalse);
    });

    test('closes a pause that was left open, so its time stops growing', () {
      final body = castingBody(pauses: [
        <String, Object?>{
          'uuid': 'p0',
          'truckSeq': 1,
          'startAt': '2026-10-08T08:10:00+07:00',
          'endAt': null,
          'reason': 'tunggu_tm',
          'note': null,
        },
      ]);
      applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expectSameMoment(storedPauses(body).single['endAt'], at);
      // 08:00 → 08:20 with 08:10 → 08:20 paused = 10 minutes of pouring.
      expect(pouringTime(truckOf(body), storedPauses(body), at.add(const Duration(hours: 2))), const Duration(minutes: 10));
    });

    test('ignores an already finished TM: the newest running one is stopped', () {
      final body = castingBody(finishedTruck: true);
      final r = applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expect(r.seq, 2);
      final newest = ((body['trucks'] as List)[1] as Map).cast<String, Object?>();
      expectSameMoment(newest['endAt'], at);
      // The TM that was already finished is left exactly as it was.
      expectSameMoment(((body['trucks'] as List).first as Map)['endAt'], DateTime.parse('2026-10-08T07:30:00+07:00'));
    });

    test('refused when no TM is being poured', () {
      final body = castingBody(running: false);
      final r = applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expect(r.applied, isFalse);
      expect(r.refusal, isNotNull);
      expect(truckOf(body)['endAt'], isNull);
    });

    test('refused when the casting log is already finished', () {
      final body = castingBody(status: 'selesai');
      final r = applyTruckCommand(body, TruckCommand.finish, at: at, pauseUuid: 'p1');
      expect(r.applied, isFalse);
      expect(truckOf(body)['endAt'], isNull);
    });
  });

  group('pause', () {
    test('stores the pause in the body itself, not in a copy', () {
      final body = castingBody();
      final r = applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p9', pauseReason: 'kendala_alat');
      expect(r.applied, isTrue);
      final stored = storedPauses(body);
      expect(stored, hasLength(1));
      expect(stored.single['uuid'], 'p9');
      expect(stored.single['truckSeq'], 1);
      expect(stored.single['reason'], 'kendala_alat');
      expect(stored.single['endAt'], isNull);
      expectSameMoment(stored.single['startAt'], at);
    });

    test('stops the clock for real', () {
      final body = castingBody();
      applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p9');
      final later = at.add(const Duration(minutes: 10));
      // 20 min poured, then 10 min paused — not 30 min poured.
      expect(pouringTime(truckOf(body), storedPauses(body), later), const Duration(minutes: 20));
    });

    test('works on an older document that has no pauses list yet', () {
      final body = castingBody()..remove('pauses');
      final r = applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p9');
      expect(r.applied, isTrue);
      expect(storedPauses(body), hasLength(1));
    });

    test('refused while the TM is already paused', () {
      final body = castingBody();
      applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p1');
      final second = applyTruckCommand(body, TruckCommand.pause, at: at.add(const Duration(minutes: 1)), pauseUuid: 'p2');
      expect(second.applied, isFalse);
      expect(storedPauses(body), hasLength(1));
    });

    test('refused when no TM is being poured', () {
      final body = castingBody(running: false);
      final r = applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p1');
      expect(r.applied, isFalse);
      expect(storedPauses(body), isEmpty);
    });

    test('a pause of another TM does not block this one', () {
      final body = castingBody(pauses: [
        <String, Object?>{'uuid': 'p0', 'truckSeq': 7, 'startAt': '2026-10-08T08:00:00+07:00', 'endAt': null, 'reason': 'lainnya'},
      ]);
      final r = applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p1');
      expect(r.applied, isTrue);
      expect(storedPauses(body), hasLength(2));
    });
  });

  group('resume', () {
    test('closes the open pause', () {
      final body = castingBody();
      applyTruckCommand(body, TruckCommand.pause, at: at, pauseUuid: 'p1');
      final r = applyTruckCommand(body, TruckCommand.resume, at: at.add(const Duration(minutes: 5)), pauseUuid: 'p2');
      expect(r.applied, isTrue);
      expectSameMoment(storedPauses(body).single['endAt'], at.add(const Duration(minutes: 5)));
      expect(openPause(storedPauses(body), 1), isNull);
    });

    test('refused when the TM is not paused', () {
      final body = castingBody();
      final r = applyTruckCommand(body, TruckCommand.resume, at: at, pauseUuid: 'p1');
      expect(r.applied, isFalse);
      expect(r.refusal, isNotNull);
    });

    test('refused when no TM is being poured', () {
      final body = castingBody(running: false);
      expect(applyTruckCommand(body, TruckCommand.resume, at: at, pauseUuid: 'p1').applied, isFalse);
    });
  });

  group('runningTruckOf', () {
    test('ignores a TM that is not started or already finished', () {
      expect(runningTruckOf(castingBody(running: false)), isNull);
      final finished = castingBody();
      truckOf(finished)['endAt'] = '2026-10-08T08:30:00+07:00';
      expect(runningTruckOf(finished), isNull);
    });

    test('picks the highest seq when two are open', () {
      final body = castingBody();
      (body['trucks'] as List).add(<String, Object?>{
        'uuid': 'tm-9',
        'seq': 9,
        'startAt': '2026-10-08T08:05:00+07:00',
        'endAt': null,
      });
      expect(runningTruckOf(body)?['seq'], 9);
    });

    test('tolerates a document with no trucks at all', () {
      expect(runningTruckOf({'status': 'berjalan'}), isNull);
    });
  });
}
