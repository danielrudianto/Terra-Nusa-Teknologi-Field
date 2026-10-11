import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/casting_state.dart';
import 'package:terrabot_field/features/casting/calc/volume.dart';

void main() {
  // D1000 (0.7854 m²/m), drilled 20.4 m, gap 0.30 → tremie must reach 20.1 m.
  const g = PileGeometry(diameterMm: 1000, groundLevel: 10, cutOffLevel: 8.5, tipLevel: -10, drilledDepthM: 20.4);

  CastingState casting({required List<String> segments, List<Map<String, Object?>> trucks = const []}) => CastingState.from(g, {
        'tremieBottomGapM': '0.30',
        'tremie': [
          for (var i = 0; i < segments.length; i++) {'uuid': '$i', 'position': i + 1, 'lengthM': segments[i]},
        ],
        'trucks': trucks,
      });

  group('tremie reaches the bottom', () {
    test('20 m of tremie for 20.1 m: within the 10 cm slack', () {
      expect(casting(segments: ['2', '3', '3', '3', '3', '3', '3']).tremieReachesBottom, isTrue);
    });
    test('18 m of tremie for 20.1 m: too short', () {
      expect(casting(segments: ['3', '3', '3', '3', '3', '3']).tremieReachesBottom, isFalse);
    });
  });

  group('tremie too long', () {
    test('20 m for 20.1 m: just short, not too long', () {
      final k = casting(segments: ['2', '3', '3', '3', '3', '3', '3']);
      expect(k.tremieStickUpM, closeTo(-0.1, 1e-9));
      expect(k.tremieTooLong, isFalse);
    });
    test('23 m: 2.9 m above GS, still reachable', () {
      expect(casting(segments: ['2', '3', '3', '3', '3', '3', '3', '3']).tremieTooLong, isFalse);
    });
    test('26 m in a 20 m hole: too long', () {
      final k = casting(segments: ['2', '3', '3', '3', '3', '3', '3', '3', '3']);
      expect(k.tremieStickUpM, closeTo(5.9, 1e-9));
      expect(k.tremieTooLong, isTrue);
    });
    test('adding 3 m to 22 m would pass the limit', () {
      final k = casting(segments: ['1', '3', '3', '3', '3', '3', '3', '3']);
      expect(k.stickUpWith(3) > tremieStickUpMaxM, isTrue);
      expect(k.stickUpWith(1) > tremieStickUpMaxM, isFalse);
    });
  });

  group('concrete used so far', () {
    test('no sounding: no judgement', () {
      final k = casting(segments: ['3'], trucks: [
        {'seq': 1, 'volumeM3': '7'},
      ]);
      expect(k.overuseSoFarPercent(1), isNull);
    });

    test('7 m³ for 7.854 m³ of hole is under theory', () {
      // Level 10.4 m: 10 m of hole × 0.7854 = 7.854 m³.
      final k = casting(segments: ['3'], trucks: [
        {'seq': 1, 'volumeM3': '7', 'concreteDepthAfterM': '10.4'},
      ]);
      expect(k.overuseSoFarPercent(1), closeTo(-10.87, 0.01));
    });

    test('9.5 m³ for the same 10 m is about 21 % over', () {
      final k = casting(segments: ['3'], trucks: [
        {'seq': 1, 'volumeM3': '9.5', 'concreteDepthAfterM': '10.4'},
      ]);
      expect(k.overuseSoFarPercent(1)! > overuseWarnPercent, isTrue);
    });
  });
}
