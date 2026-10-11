import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/casting_state.dart';
import 'package:terrabot_field/features/casting/calc/cut_plan.dart';
import 'package:terrabot_field/features/casting/calc/volume.dart';

// Expected numbers are taken from the Python prototype (proto/rencana.py) that
// was run with the same inputs.

List<Segment> _segments(List<double> lengthM) =>
    [for (var i = 0; i < lengthM.length; i++) Segment(key: '${i + 1}', lengthM: lengthM[i])];

void main() {
  group('chooseSegmentsToRemove', () {
    test('remove from the top until ≥ 2 m target remains', () {
      final p = chooseSegmentsToRemove(_segments([3, 3, 3, 3, 3]), 5.6, const EmbedmentLimits());
      expect(p.map((s) => s.lengthM), [3]);
    });

    test('the bottom-most segment is never removed', () {
      final p = chooseSegmentsToRemove(_segments([3]), 9, const EmbedmentLimits());
      expect(p, isEmpty);
    });

    test('if the target is not reached, use the 1 m minimum', () {
      // embedment 4.5; top segment 3 → remaining 1.5 (< 2 but ≥ 1)
      final p = chooseSegmentsToRemove(_segments([3, 3]), 4.5, const EmbedmentLimits());
      expect(p.map((s) => s.lengthM), [3]);
    });

    test('nothing can be removed without dropping below the minimum', () {
      final p = chooseSegmentsToRemove(_segments([3, 3]), 3.5, const EmbedmentLimits());
      expect(p, isEmpty);
    });

    test('result order = removal order (top first)', () {
      final p = chooseSegmentsToRemove(_segments([3, 3, 3, 3, 3, 3, 2, 1]), 5.94, const EmbedmentLimits());
      expect(p.map((s) => s.key), ['8', '7']);
    });
  });

  group('planTruck', () {
    test('D1000, 7 m³: one cut of 1+2 m after 4.9 m³', () {
      final r = planTruck(
        diameterMm: 1000,
        tremieBottomM: 19.7,
        segments: _segments([3, 3, 3, 3, 3, 3, 2, 1]),
        concreteDepthM: 20.0,
        cutOffDepthM: 1.5,
        volumeM3: 7,
        isFirstTruck: true,
      );
      expect(r.cuts, hasLength(1));
      expect(r.cuts.single.afterM3, 4.9);
      expect(r.cuts.single.toRemove.map((s) => s.lengthM), [1, 2]);
      expect(r.cuts.single.embedmentBeforeM, 5.94);
      expect(r.cuts.single.embedmentAfterM, 2.94);
      expect(r.finalEmbedmentM, 5.61);
      expect(r.finalConcreteDepthM, 11.09);
      expect(r.remainingSegments, hasLength(6));
      expect(r.cutOffReached, isFalse);
      expect(r.warnings, isEmpty);
    });

    test('D800, 7 m³: three cuts', () {
      final r = planTruck(
        diameterMm: 800,
        tremieBottomM: 19.7,
        segments: _segments([3, 3, 3, 3, 3, 3, 2, 1]),
        concreteDepthM: 20.0,
        cutOffDepthM: 1.5,
        volumeM3: 7,
        isFirstTruck: true,
      );
      expect(r.cuts.map((p) => p.afterM3), [3.15, 4.65, 6.15]);
      expect(r.cuts.map((p) => p.embedmentAfterM), [2.97, 2.95, 2.94]);
      expect(r.finalEmbedmentM, 4.63);
      expect(r.finalConcreteDepthM, 6.07);
      expect(r.remainingSegments, hasLength(4));
    });

    test('concrete stops at the cut-off', () {
      final r = planTruck(
        diameterMm: 600,
        tremieBottomM: 3.0,
        segments: _segments([3, 1]),
        concreteDepthM: 2.5,
        cutOffDepthM: 1.5,
        volumeM3: 5,
      );
      expect(r.finalConcreteDepthM, 1.5);
      expect(r.cutOffReached, isTrue);
    });

    test('first TM: tremie tip above the bottom is NOT a warning', () {
      final r = planTruck(
        diameterMm: 1000,
        tremieBottomM: 19.7,
        segments: _segments([3, 3, 3, 3, 3, 3, 2, 1]),
        concreteDepthM: 20.0,
        cutOffDepthM: 1.5,
        volumeM3: 1,
        isFirstTruck: true,
      );
      expect(r.warnings, isEmpty);
    });

    test('short embedment in the middle of casting is warned about', () {
      final r = planTruck(
        diameterMm: 1000,
        tremieBottomM: 10.0,
        segments: _segments([3, 3, 3]),
        concreteDepthM: 9.6,
        cutOffDepthM: 1.5,
        volumeM3: 0.5,
      );
      expect(r.warnings.first.kind, WarningKind.embedmentTooShort);
    });
  });

  group('geometry', () {
    const g = PileGeometry(diameterMm: 1000, groundLevel: 10, cutOffLevel: 8.5, tipLevel: -10, drilledDepthM: 20.4);

    test('length & volume', () {
      expect(g.cutOffDepthM, 1.5);
      expect(g.plannedDrillLengthM, 20);
      expect(g.plannedEffectiveLengthM, 18.5);
      expect(g.actualEffectiveLengthM, closeTo(18.9, 1e-9));
      expect(g.plannedTheoreticalVolumeM3, closeTo(14.5299, 1e-3));
    });

    test('casting state: bottom tip rises by the length of the removed segments', () {
      final k = CastingState.from(g, {
        'tremieBottomGapM': '0.30',
        'tremie': [
          {'uuid': 'a', 'position': 1, 'lengthM': '3.00'},
          {'uuid': 'b', 'position': 2, 'lengthM': '3.00'},
          {'uuid': 'c', 'position': 3, 'lengthM': '2.00', 'removedAfterTruckSeq': 1},
        ],
        'trucks': [
          {'seq': 1, 'volumeM3': '7.00', 'concreteDepthAfterM': '11.2'},
        ],
      });
      expect(k.tremieBottomAfter(0), closeTo(20.1, 1e-9));
      expect(k.tremieBottomAfter(1), closeTo(18.1, 1e-9));
      expect(k.installedLengthAfter(1), 6);
      expect(k.concreteAfter(1).depthM, 11.2);
      expect(k.concreteAfter(1).measured, isTrue);
      expect(k.embedmentAfter(1), closeTo(6.9, 1e-9));
    });
  });
}
