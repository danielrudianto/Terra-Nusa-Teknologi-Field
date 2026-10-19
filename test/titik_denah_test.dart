import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/pile_point_data.dart';
import 'package:terrabot_field/features/casting/titik_denah.dart';

/// Denah titik. Yang diuji di sini adalah kesalahan yang membuat gambarnya
/// TETAP tampak masuk akal: skala berbeda di dua sumbu, dan sumbu Y yang
/// tercermin. Aturannya harus sama dengan web
/// (`helpers/titik-denah.helper.ts` + `titik-denah.spec.ts`).
void main() {
  FieldPilePoint titik({
    required String kode,
    int? id,
    String status = 'belum_bor',
    double? dx,
    double? dy,
    double? ax,
    double? ay,
  }) =>
      FieldPilePoint(server: {
        'id': id,
        'uuid': kode,
        'code': kode,
        'status': status,
        'designX': dx,
        'designY': dy,
        'actualX': ax,
        'actualY': ay,
      });

  test('tanpa satu pun koordinat: null, bukan kotak kosong', () {
    expect(susunDenah([titik(kode: 'P1')]), isNull);
  });

  test('titik tanpa koordinat dihitung, tidak digambar', () {
    final d = susunDenah([
      titik(kode: 'P1', dx: 100, dy: 100),
      titik(kode: 'P2', dx: 110, dy: 100),
      titik(kode: 'P3'),
    ])!;
    expect(d.titik.map((t) => t.kode), ['P1', 'P2']);
    expect(d.tanpaKoordinat, 1);
  });

  test('SKALA X DAN Y SAMA', () {
    final d = susunDenah(
      [
        titik(kode: 'A', dx: 0, dy: 0),
        titik(kode: 'B', dx: 40, dy: 0),
        titik(kode: 'C', dx: 0, dy: 10),
      ],
      lebar: 1000,
      tinggi: 700,
      tepi: 0,
    )!;
    final a = d.titik.firstWhere((t) => t.kode == 'A');
    final b = d.titik.firstWhere((t) => t.kode == 'B');
    final c = d.titik.firstWhere((t) => t.kode == 'C');
    final perMeterX = (b.posisi.dx - a.posisi.dx) / 40;
    final perMeterY = (a.posisi.dy - c.posisi.dy) / 10;
    expect(perMeterY, closeTo(perMeterX, 1e-9));
  });

  test('SUMBU Y TERBALIK — Y lapangan lebih besar digambar lebih ATAS', () {
    final d = susunDenah(
      [
        titik(kode: 'bawah', dx: 0, dy: 0),
        titik(kode: 'atas', dx: 0, dy: 50),
      ],
      lebar: 400,
      tinggi: 400,
    )!;
    final bawah = d.titik.firstWhere((t) => t.kode == 'bawah');
    final atas = d.titik.firstWhere((t) => t.kode == 'atas');
    expect(atas.posisi.dy, lessThan(bawah.posisi.dy));
  });

  test('satu titik saja: tidak membagi dengan nol, mendarat di tengah', () {
    final d = susunDenah(
      [titik(kode: 'P1', dx: 7, dy: 9)],
      lebar: 400,
      tinggi: 200,
    )!;
    expect(d.titik, hasLength(1));
    expect(d.titik.single.posisi.dx, closeTo(200, 1e-9));
    expect(d.titik.single.posisi.dy, closeTo(100, 1e-9));
  });

  test('digambar di posisi AKTUAL, dengan garis ke rencananya', () {
    final d = susunDenah(
      [
        titik(kode: 'A', dx: 0, dy: 0, ax: 0.05, ay: 0),
        titik(kode: 'B', dx: 30, dy: 0),
      ],
      lebar: 600,
      tinggi: 400,
    )!;
    final a = d.titik.firstWhere((t) => t.kode == 'A');
    expect(a.rencana, isNotNull);
    // Tanpa aktual, yang tergambar ITU rencananya — tidak ada garis.
    expect(d.titik.firstWhere((t) => t.kode == 'B').rencana, isNull);
  });

  test('tanpa rencana pun tetap tergambar, memakai aktualnya', () {
    final d = susunDenah(
      [
        titik(kode: 'A', ax: 10, ay: 10),
        titik(kode: 'B', ax: 20, ay: 10),
      ],
      lebar: 600,
      tinggi: 400,
    )!;
    expect(d.titik, hasLength(2));
    expect(d.tanpaKoordinat, 0);
    expect(d.titik.every((t) => t.rencana == null), isTrue);
  });

  group('keadaan', () {
    test('cor berjalan di HP ini: SEDANG dicor, bukan sudah', () {
      final d = susunDenah([
        titik(kode: 'A', status: 'belum_bor', dx: 0, dy: 0),
        titik(kode: 'B', status: 'sudah_bor', dx: 10, dy: 0),
        titik(kode: 'C', status: 'sudah_cor', dx: 20, dy: 0),
      ])!;
      expect(d.hitungan[KeadaanTitik.belumBor], 1);
      expect(d.hitungan[KeadaanTitik.sudahBor], 1);
      expect(d.hitungan[KeadaanTitik.sudahCor], 1);
    });

    test('log cor di HP lain yang masih terbuka: SEDANG dicor', () {
      const p = FieldPilePoint(server: {
        'uuid': 'x',
        'code': 'X',
        'status': 'sudah_bor',
        'castingUuid': 'c1',
        'designX': 0,
        'designY': 0,
      });
      expect(keadaanTitik(p), KeadaanTitik.sedangCor);
    });

    test('log bor di HP lain yang masih terbuka: SEDANG dibor', () {
      const p = FieldPilePoint(server: {
        'uuid': 'x',
        'code': 'X',
        'status': 'belum_bor',
        'drillLogUuid': 'd1',
        'drillLogStatus': 'berjalan',
        'designX': 0,
        'designY': 0,
      });
      expect(keadaanTitik(p), KeadaanTitik.sedangBor);
    });
  });

  test('yang SEDANG dikerjakan berongga, yang sudah terisi', () {
    expect(gayaKeadaan[KeadaanTitik.sedangBor]!.isi, isNull);
    expect(gayaKeadaan[KeadaanTitik.sedangCor]!.isi, isNull);
    expect(gayaKeadaan[KeadaanTitik.sudahBor]!.isi, isNotNull);
    expect(gayaKeadaan[KeadaanTitik.sudahCor]!.isi, isNotNull);
    expect(gayaKeadaan[KeadaanTitik.belumBor]!.isi, isNotNull);
  });

  test('WARNANYA SAMA DENGAN WEB', () {
    // Angkanya ditulis ulang di sini dengan sengaja: ini satu-satunya
    // tempat yang akan berteriak kalau salah satu sisi diubah sendiri.
    expect(gayaKeadaan[KeadaanTitik.belumBor]!.isi!.toARGB32(), 0xFFD9DCE1);
    expect(gayaKeadaan[KeadaanTitik.sudahBor]!.isi!.toARGB32(), 0xFFC62828);
    expect(gayaKeadaan[KeadaanTitik.sudahCor]!.isi!.toARGB32(), 0xFF1565C0);
  });

  group('meterBulat', () {
    test('membulatkan ke 1 / 2 / 5 kali pangkat sepuluh', () {
      expect(meterBulat(1), 1);
      expect(meterBulat(3), 2);
      expect(meterBulat(7), 5);
      expect(meterBulat(12), 10);
      expect(meterBulat(37.4), 20);
      expect(meterBulat(0.4), closeTo(0.2, 1e-9));
    });

    test('nol dan angka tak masuk akal tidak membuat batang selebar nol', () {
      expect(meterBulat(0), 1);
      expect(meterBulat(double.nan), 1);
      expect(meterBulat(-5), 1);
    });
  });

  test('batang skalanya bulat dan masuk di dalam kotak', () {
    final d = susunDenah(
      [
        titik(kode: 'A', dx: 0, dy: 0),
        titik(kode: 'B', dx: 37.4, dy: 12),
      ],
      lebar: 1000,
      tinggi: 700,
    )!;
    expect([1.0, 2.0, 5.0, 10.0, 20.0, 50.0], contains(d.meterBatang));
    expect(d.batangSkala, lessThan(d.lebar));
  });

  test('id server dibawa, supaya titiknya dapat diketuk', () {
    final d = susunDenah([titik(kode: 'A', id: 42, dx: 1, dy: 1)])!;
    expect(d.titik.single.id, 42);
    expect(d.titik.single.posisi, isA<Offset>());
  });
}
