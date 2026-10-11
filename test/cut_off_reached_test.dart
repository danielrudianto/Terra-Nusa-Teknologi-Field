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

  group('sounding after a truck', () {
    test('a rise is fine', () => expect(soundingProblem(8.0, before: 12.0, bottom: 20.4), isNull));
    test('the tape\'s 10 cm of slack is fine', () => expect(soundingProblem(12.08, before: 12.0, bottom: 20.4), isNull));
    test('deeper than before is refused', () => expect(soundingProblem(13.0, before: 12.0, bottom: 20.4), isNotNull));
    test('below the hole bottom is refused', () => expect(soundingProblem(21.0, before: 22.0, bottom: 20.4), isNotNull));
  });
}
