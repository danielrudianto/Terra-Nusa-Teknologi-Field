import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/concrete_profile.dart';

/// Profil beton (28 Nov 2026): bos membaca "Ø 1,23 m" di samping "+5,3%",
/// menghitung 1.230/1.200 = +2,5%, dan mengira hitungannya salah.
///
/// Yang dijaga: persen = selisih VOLUME, diameter = Ø rencana × √rasio,
/// jadi selisih diameternya kira-kira separuh selisih volume. Contoh bos
/// sendiri dipakai sebagai angka uji.
void main() {
  const d = 1200; // mm
  final luas = math.pi / 4 * 1.2 * 1.2;

  Map<String, Object?> tm(int seq, double bawah, double atas, double vol) => {
        'seq': seq,
        'volumeM3': vol,
        'concreteDepthBeforeM': bawah,
        'concreteDepthAfterM': atas,
      };

  test('volume +5,3% → Ø efektif ≈ 1.231 mm (+2,6%), bukan +5,3%', () {
    final s = concreteSegments([tm(1, 10, 5, luas * 5 * 1.053)], d, 10).single;
    expect(s.ratio, closeTo(1.053, 1e-9));
    expect(s.diameterM! * 1000, closeTo(1231.4, 0.1));
    expect((s.diameterM! / 1.2 - 1) * 100, closeTo(2.6, 0.05));
    expect(s.kind, SegmentKind.fits);
  });

  test('volume −3,5% → Ø ≈ 1.179 mm; +7,4% → Ø ≈ 1.244 mm', () {
    final a = concreteSegments([tm(1, 10, 5, luas * 5 * 0.965)], d, 10).single;
    final b = concreteSegments([tm(1, 10, 5, luas * 5 * 1.074)], d, 10).single;
    expect(a.diameterM! * 1000, closeTo(1178.8, 0.1));
    // Batas necking −3%, sama dengan Office (28 Nov 2026).
    expect(a.kind, SegmentKind.necking);
    expect(b.diameterM! * 1000, closeTo(1243.6, 0.1));
  });

  test('batas necking −3%: −2,9% masih sesuai, −3,1% necking', () {
    SegmentKind jenis(double r) => concreteSegments([tm(1, 10, 5, luas * 5 * r)], d, 10).single.kind;
    expect(jenis(0.971), SegmentKind.fits);
    expect(jenis(0.969), SegmentKind.necking);
    expect(neckingLimit, 0.03);
  });
}
