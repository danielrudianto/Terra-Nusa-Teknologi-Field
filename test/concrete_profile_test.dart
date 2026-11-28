import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/concrete_profile.dart';

/// Profil beton (28 Nov 2026).
///
/// 1. Bos membaca "Ø 1,23 m" di samping "+5,3%", menghitung 1.230/1.200 =
///    +2,5%, dan mengira hitungannya salah: +5,3% itu selisih VOLUME.
///    Diameter = Ø rencana × √rasio volume.
/// 2. Keputusan bos: dinilai dari DIAMETER — necking di bawah −5% diameter,
///    bulking di atas +10% diameter. Sama dengan Office.
void main() {
  const d = 1200; // mm
  final luas = math.pi / 4 * 1.2 * 1.2;

  Map<String, Object?> tm(int seq, double bawah, double atas, double vol) => {
        'seq': seq,
        'volumeM3': vol,
        'concreteDepthBeforeM': bawah,
        'concreteDepthAfterM': atas,
      };

  SegmentKind jenis(double rasioVolume) =>
      concreteSegments([tm(1, 10, 5, luas * 5 * rasioVolume)], d, 10).single.kind;

  test('volume +5,3% → Ø efektif ≈ 1.231 mm (+2,6%), bukan +5,3%', () {
    final s = concreteSegments([tm(1, 10, 5, luas * 5 * 1.053)], d, 10).single;
    expect(s.ratio, closeTo(1.053, 1e-9));
    expect(s.diameterM! * 1000, closeTo(1231.4, 0.1));
    expect((s.diameterM! / 1.2 - 1) * 100, closeTo(2.6, 0.05));
    expect(s.kind, SegmentKind.fits);
  });

  test('necking dinilai dari DIAMETER: −4,9% sesuai, −5,1% necking', () {
    expect(jenis(0.951 * 0.951), SegmentKind.fits);
    expect(jenis(0.949 * 0.949), SegmentKind.necking);
    // Volume −7% = diameter −3,6%: sesuai (dulu, dinilai dari volume: necking).
    expect(jenis(0.93), SegmentKind.fits);
    expect(neckingLimit, 0.05);
  });

  test('bulking dinilai dari DIAMETER: +9,9% sesuai, +10,1% bulking', () {
    expect(jenis(1.099 * 1.099), SegmentKind.fits);
    expect(jenis(1.101 * 1.101), SegmentKind.bulking);
    // Volume +20% = diameter +9,5%: sesuai (dulu: bulking).
    expect(jenis(1.2), SegmentKind.fits);
    expect(bulkingLimit, 0.10);
  });

  test('BTA PIT 80% (luas) = diameter 89,4%: necking', () {
    final s = concreteSegments([tm(1, 10, 5, luas * 5 * 0.8)], d, 10).single;
    expect(s.diameterM! / 1.2, closeTo(0.894, 0.001));
    expect(s.kind, SegmentKind.necking);
  });
}
