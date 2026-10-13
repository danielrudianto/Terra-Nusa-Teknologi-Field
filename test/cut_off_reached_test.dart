import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/casting_state.dart';
import 'package:terrabot_field/features/casting/calc/volume.dart';

void main() {
  // GS +10, cut-off +8.5 → cut-off 1.5 m below ground.
  const g = PileGeometry(diameterMm: 1000, groundLevel: 10, cutOffLevel: 8.5, tipLevel: -10, drilledDepthM: 20.4);

  CastingState casting(String? soundedAfter) => CastingState.from(g, {
        'tremie': const [],
        'trucks': [
          {'seq': 1, 'volumeM3': '7.00', 'concreteDepthAfterM': soundedAfter},
        ],
      });

  test('sounded above cut-off: reached', () {
    expect(casting('1.20').reachedCutOffAfter(1), isTrue);
  });

  test('sounded exactly at cut-off: reached', () {
    expect(casting('1.50').reachedCutOffAfter(1), isTrue);
  });

  test('still below cut-off: not reached', () {
    expect(casting('4.00').reachedCutOffAfter(1), isFalse);
  });

  test('before the first truck: never', () {
    expect(casting(null).reachedCutOffAfter(0), isFalse);
  });

  group('shortfall to cut-off', () {
    // D1000 = 0,785 m² per metre of column.
    const area = 0.7853981633974483;

    test('a small shortfall needs no explaining: the trim covers it', () {
      final s = shortfallToCutOff(missingM: 0.40, areaM2: area, averageTruckM3: 7);
      expect(s.mustExplain, isFalse);
    });

    test('past the slack it must be explained', () {
      expect(shortfallToCutOff(missingM: 0.60, areaM2: area).mustExplain, isTrue);
    });

    test('metres become m3 and truckloads', () {
      // 10 m of D1000 = 7,85 m3; with 7 m3 trucks that is 2 more TM.
      final s = shortfallToCutOff(missingM: 10, areaM2: area, averageTruckM3: 7);
      expect(s.volumeM3, closeTo(7.854, 0.001));
      expect(s.trucks, 2);
      expect(s.mustExplain, isTrue);
    });

    test('this pile\'s own average truck is used, not a guess', () {
      // Daniel's case: 5 TM planned, 1 poured. With 4 m3 trucks the same
      // hole needs twice as many loads as with 8 m3 ones.
      expect(shortfallToCutOff(missingM: 10, areaM2: area, averageTruckM3: 4).trucks, 2);
      expect(shortfallToCutOff(missingM: 20, areaM2: area, averageTruckM3: 4).trucks, 4);
      expect(shortfallToCutOff(missingM: 20, areaM2: area, averageTruckM3: 8).trucks, 2);
    });

    test('no truck recorded yet falls back to a usual load', () {
      final s = shortfallToCutOff(missingM: 20, areaM2: area);
      expect(s.trucks, (20 * area / truckVolumeTypicalM3).ceil());
    });

    test('at or past cut-off there is nothing missing', () {
      final s = shortfallToCutOff(missingM: -0.30, areaM2: area);
      expect(s.volumeM3, 0);
      expect(s.trucks, 0);
      expect(s.mustExplain, isFalse);
    });
  });

  group('sounding after a truck', () {
    test('a rise is fine', () => expect(soundingProblem(8.0, before: 12.0, bottom: 20.4), isNull));
    test('the tape\'s 10 cm of slack is fine', () => expect(soundingProblem(12.08, before: 12.0, bottom: 20.4), isNull));
    test('deeper than before is refused', () => expect(soundingProblem(13.0, before: 12.0, bottom: 20.4), isNotNull));
    test('below the hole bottom is refused', () => expect(soundingProblem(21.0, before: 22.0, bottom: 20.4), isNotNull));
  });

group('overuse if a truck is added', () {
    // 10 m³ of hole. The figures below are what the TM sheet checks before
    // anything is poured.
    test('still under theory', () => expect(overuseIfAdded(theoreticalM3: 10, pouredSoFarM3: 0, addM3: 7), lessThan(0)));
    test('exactly on theory is 0%', () => expect(overuseIfAdded(theoreticalM3: 10, pouredSoFarM3: 3, addM3: 7), closeTo(0, 0.001)));
    test('a little over warns', () {
      final over = overuseIfAdded(theoreticalM3: 10, pouredSoFarM3: 7, addM3: 5)!;
      expect(over, closeTo(20, 0.001));
      expect(over, greaterThan(volumeWarnPercent));
      expect(over, lessThan(volumeLoudPercent));
    });
    test('a shared truck typed whole is held', () {
      // 7 m³ truck split between two piles, but typed in full on both.
      final over = overuseIfAdded(theoreticalM3: 10, pouredSoFarM3: 7, addM3: 7)!;
      expect(over, greaterThan(volumeLoudPercent));
    });
    test('no theoretical volume = nothing to say', () {
      expect(overuseIfAdded(theoreticalM3: 0, pouredSoFarM3: 5, addM3: 7), isNull);
    });
  });
}
