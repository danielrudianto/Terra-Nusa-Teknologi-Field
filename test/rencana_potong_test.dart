import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/fitur/pengecoran/hitung/keadaan_cor.dart';
import 'package:terrabot_field/fitur/pengecoran/hitung/rencana_potong.dart';
import 'package:terrabot_field/fitur/pengecoran/hitung/volume.dart';

// Angka harapan diambil dari prototipe Python (proto/rencana.py) yang
// dijalankan dengan masukan yang sama.

List<Segmen> _seg(List<double> panjang) =>
    [for (var i = 0; i < panjang.length; i++) Segmen(kunci: '${i + 1}', panjangM: panjang[i])];

void main() {
  group('pilihCabut', () {
    test('cabut dari atas sampai tersisa ≥ sasaran 2 m', () {
      final p = pilihCabut(_seg([3, 3, 3, 3, 3]), 5.6, const BatasTertanam());
      expect(p.map((s) => s.panjangM), [3]);
    });

    test('segmen paling bawah tidak pernah dicabut', () {
      final p = pilihCabut(_seg([3]), 9, const BatasTertanam());
      expect(p, isEmpty);
    });

    test('bila sasaran tak tercapai, pakai minimum 1 m', () {
      // tertanam 4,5; segmen atas 3 → sisa 1,5 (< 2 tapi ≥ 1)
      final p = pilihCabut(_seg([3, 3]), 4.5, const BatasTertanam());
      expect(p.map((s) => s.panjangM), [3]);
    });

    test('tidak ada yang dapat dicabut tanpa jatuh di bawah minimum', () {
      final p = pilihCabut(_seg([3, 3]), 3.5, const BatasTertanam());
      expect(p, isEmpty);
    });

    test('urutan hasil = urutan mencabut (atas dulu)', () {
      final p = pilihCabut(_seg([3, 3, 3, 3, 3, 3, 2, 1]), 5.94, const BatasTertanam());
      expect(p.map((s) => s.kunci), ['8', '7']);
    });
  });

  group('rencanakanTm', () {
    test('D1000, 7 m³: satu potong 1+2 m setelah 4,9 m³', () {
      final r = rencanakanTm(
        diameterMm: 1000,
        ujungBawahM: 19.7,
        segmen: _seg([3, 3, 3, 3, 3, 3, 2, 1]),
        kedalamanBetonM: 20.0,
        kedalamanCutOffM: 1.5,
        volumeM3: 7,
      );
      expect(r.potong, hasLength(1));
      expect(r.potong.single.setelahM3, 4.9);
      expect(r.potong.single.cabut.map((s) => s.panjangM), [1, 2]);
      expect(r.potong.single.tertanamSebelumM, 5.94);
      expect(r.potong.single.tertanamSesudahM, 2.94);
      expect(r.tertanamAkhirM, 5.61);
      expect(r.kedalamanBetonAkhirM, 11.09);
      expect(r.segmenSisa, hasLength(6));
      expect(r.cutOffTercapai, isFalse);
      expect(r.peringatan, isEmpty);
    });

    test('D800, 7 m³: tiga kali potong', () {
      final r = rencanakanTm(
        diameterMm: 800,
        ujungBawahM: 19.7,
        segmen: _seg([3, 3, 3, 3, 3, 3, 2, 1]),
        kedalamanBetonM: 20.0,
        kedalamanCutOffM: 1.5,
        volumeM3: 7,
      );
      expect(r.potong.map((p) => p.setelahM3), [3.15, 4.65, 6.15]);
      expect(r.potong.map((p) => p.tertanamSesudahM), [2.97, 2.95, 2.94]);
      expect(r.tertanamAkhirM, 4.63);
      expect(r.kedalamanBetonAkhirM, 6.07);
      expect(r.segmenSisa, hasLength(4));
    });

    test('beton berhenti di cut-off', () {
      final r = rencanakanTm(
        diameterMm: 600,
        ujungBawahM: 3.0,
        segmen: _seg([3, 1]),
        kedalamanBetonM: 2.5,
        kedalamanCutOffM: 1.5,
        volumeM3: 5,
      );
      expect(r.kedalamanBetonAkhirM, 1.5);
      expect(r.cutOffTercapai, isTrue);
    });

    test('tertanam kurang sejak awal diperingatkan', () {
      final r = rencanakanTm(
        diameterMm: 1000,
        ujungBawahM: 10.0,
        segmen: _seg([3, 3, 3]),
        kedalamanBetonM: 9.6,
        kedalamanCutOffM: 1.5,
        volumeM3: 0.5,
      );
      expect(r.peringatan.first.jenis, JenisPeringatan.tertanamKurang);
    });
  });

  group('geometri', () {
    const g = GeometriTitik(diameterMm: 1000, groundLevel: 10, cutOffLevel: 8.5, tipLevel: -10, drilledDepthM: 20.4);

    test('panjang & volume', () {
      expect(g.kedalamanCutOffM, 1.5);
      expect(g.panjangBorRencanaM, 20);
      expect(g.panjangEfektifRencanaM, 18.5);
      expect(g.panjangEfektifAktualM, closeTo(18.9, 1e-9));
      expect(g.volumeTeoritisRencanaM3, closeTo(14.5299, 1e-3));
    });

    test('keadaan cor: ujung bawah naik sepanjang segmen yang dicabut', () {
      final k = KeadaanCor.dari(g, {
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
      expect(k.ujungBawahSetelah(0), closeTo(20.1, 1e-9));
      expect(k.ujungBawahSetelah(1), closeTo(18.1, 1e-9));
      expect(k.panjangTerpasangSetelah(1), 6);
      expect(k.betonSetelah(1).kedalamanM, 11.2);
      expect(k.betonSetelah(1).terukur, isTrue);
      expect(k.tertanamSetelah(1), closeTo(6.9, 1e-9));
    });
  });
}
