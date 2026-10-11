import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/pile_point_data.dart';

void main() {
  const design = {'uuid': 'a', 'code': 'SP.B40', 'diameterMm': 800, 'cutOffLevel': -1.5, 'tipLevel': -19.5};

  test('no ground level: no depth figures, never computed from 0', () {
    const t = FieldPilePoint(server: {...design, 'groundLevel': null});
    expect(t.groundLevel, isNull);
    expect(t.geometry, isNull);
    expect(t.plannedEffectiveLengthM, 18.0, reason: 'cut-off − tip needs no GS');
    expect(t.plannedTheoreticalVolumeM3, closeTo(9.048, 0.001));
  });

  test('ground level from the drill mark on this phone counts before it is pushed', () {
    const t = FieldPilePoint(server: {...design, 'groundLevel': null}, localDrillDepthM: 20.1, localGroundLevel: 0.35);
    expect(t.geometry!.cutOffDepthM, closeTo(1.85, 1e-9));
    expect(t.geometry!.plannedDrillLengthM, closeTo(19.85, 1e-9));
  });

  test('server ground level as text (decimal over JSON) is read', () {
    const t = FieldPilePoint(server: {...design, 'groundLevel': '2.000'});
    expect(t.geometry!.cutOffDepthM, 3.5);
  });

  group('drilling on another phone', () {
    test('a drill log elsewhere, still open: being drilled, not drilled', () {
      const t = FieldPilePoint(server: {...design, 'status': 'belum_bor', 'drillLogUuid': 'x', 'drillLogStatus': 'berjalan', 'drillLogByName': 'Budi'});
      expect(t.stage, 'sedang_bor');
      expect(t.isDrilled, isFalse);
      expect(t.drillLoggedElsewhere, isTrue);
      expect(t.serverDrillLogBy, 'Budi');
    });

    test('finished elsewhere and pulled: drilled', () {
      const t = FieldPilePoint(server: {...design, 'status': 'sudah_bor', 'drillLogUuid': 'x', 'drillLogStatus': 'selesai'});
      expect(t.stage, 'sudah_bor');
      expect(t.isDrilled, isTrue);
    });

    test('no drill log anywhere: not drilled', () {
      const t = FieldPilePoint(server: {...design, 'status': 'belum_bor'});
      expect(t.stage, 'belum_bor');
      expect(t.isDrilled, isFalse);
    });
  });
}
