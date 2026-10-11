import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/casting_state.dart';
import 'package:terrabot_field/features/casting/calc/pile_snapshot.dart';
import 'package:terrabot_field/features/casting/calc/volume.dart';

void main() {
  // GS +10, cut-off +8.5 (1.5 m deep), drilled 20.4 m. D1000: 0.785 m²/m.
  const g = PileGeometry(diameterMm: 1000, groundLevel: 10, cutOffLevel: 8.5, tipLevel: -10, drilledDepthM: 20.4);

  final tremie = [
    {'uuid': 'b', 'position': 1, 'lengthM': '2.00', 'kind': 'bottom'},
    {'uuid': 's2', 'position': 2, 'lengthM': '3.00'},
    {'uuid': 's3', 'position': 3, 'lengthM': '3.00'},
    {'uuid': 's4', 'position': 4, 'lengthM': '3.00'},
    {'uuid': 's5', 'position': 5, 'lengthM': '3.00'},
    {'uuid': 's6', 'position': 6, 'lengthM': '3.00'},
    {'uuid': 's7', 'position': 7, 'lengthM': '3.00', 'removedAfterTruckSeq': 2},
  ];

  CastingState casting(List<Map<String, Object?>> trucks) =>
      CastingState.from(g, {'tremieBottomGapM': '0.30', 'tremie': tremie, 'trucks': trucks});

  test('before any concrete: level at the hole bottom, tremie 0.30 m above it', () {
    final s = pileSnapshot(casting(const []));
    expect(s.concreteNowM, 20.4);
    expect(s.tremieBottomM, closeTo(20.1, 1e-9));
    expect(s.tremieSegmentsM.first, 3.0, reason: 'listed from the top');
    expect(s.hasBottomPiece, isTrue);
    expect(s.concreteTargetM, isNull);
  });

  test('half way through a truck: level half way to where the truck ends', () {
    final k = casting([
      // π/4 × 10: exactly 10 m of rise in a D1000 hole.
      {'seq': 1, 'volumeM3': '7.853982'},
    ]);
    final s = pileSnapshot(k, pouringSeq: 1, poured: const Duration(minutes: 6), typicalPour: const Duration(minutes: 12));
    // 10 m of rise: 20.4 → 10.4 when emptied.
    expect(s.concreteTargetM, closeTo(10.4, 1e-6));
    expect(s.concreteNowM, closeTo(15.4, 1e-6));
    expect(s.concreteMeasured, isFalse);
  });

  test('a sounding after the truck is taken as is', () {
    final k = casting([
      {'seq': 1, 'volumeM3': '7.85', 'concreteDepthAfterM': '11.00'},
    ]);
    final s = pileSnapshot(k);
    expect(s.concreteNowM, 11.0);
    expect(s.concreteMeasured, isTrue);
    expect(s.embedmentM, closeTo(9.1, 1e-9));
  });

  test('a segment removed during this truck already lifts the tremie', () {
    final k = casting([
      {'seq': 1, 'volumeM3': '7.85', 'concreteDepthAfterM': '11.00'},
      {'seq': 2, 'volumeM3': '7.00'},
    ]);
    final s = pileSnapshot(k, pouringSeq: 2, poured: Duration.zero);
    expect(s.tremieBottomM, closeTo(17.1, 1e-9));
    expect(s.tremieSegmentsM.length, 6);
  });
}
