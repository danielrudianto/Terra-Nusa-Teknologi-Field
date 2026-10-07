import 'dart:math' as math;

import 'volume.dart';

/// REKOMENDASI POTONG TREMIE
///
/// Ujung bawah tremie harus selalu TERTANAM di beton segar: paling sedikit
/// 1 m (kurang dari itu, beton baru dapat menembus muka dan bercampur
/// lumpur), paling banyak 6 m (lebih dari itu, beton tidak lagi mengalir
/// keluar dan tremie dapat terjepit). Sasaran aman: sisakan ±2 m sesudah
/// setiap pemotongan.
///
/// Yang dicabut selalu segmen ATAS (yang menempel di hopper), dan segmen
/// paling bawah tidak pernah dicabut — ia yang tertanam.
///
/// Setiap kali segmen sepanjang L dicabut, seluruh tremie naik L: ujung
/// bawahnya naik L, tertanamnya berkurang L.
///
/// Algoritma ini SARAN. QS tetap yang mencentang segmen mana yang benar-
/// benar dicabut; aplikasi tidak pernah menganggap saran = kejadian.
/// Prototipenya di Python ada di catatan rancangan; angka uji di
/// `test/rencana_potong_test.dart` diambil dari prototipe itu.

class BatasTertanam {
  const BatasTertanam({this.minimumM = 1.0, this.maksimumM = 6.0, this.sasaranM = 2.0});

  final double minimumM;
  final double maksimumM;
  final double sasaranM;
}

class Segmen {
  const Segmen({required this.kunci, required this.panjangM});

  /// uuid segmen (atau indeks di uji).
  final String kunci;
  final double panjangM;
}

class SaranPotong {
  const SaranPotong({
    required this.setelahM3,
    required this.cabut,
    required this.tertanamSebelumM,
    required this.tertanamSesudahM,
  });

  /// Cabut sesudah sekian m³ dari TM ini masuk.
  final double setelahM3;

  /// Urut dari ATAS — urutan mencabutnya.
  final List<Segmen> cabut;
  final double tertanamSebelumM;
  final double tertanamSesudahM;

  double get panjangM => cabut.fold(0.0, (a, s) => a + s.panjangM);
}

enum JenisPeringatan {
  /// Tertanam akan melewati maksimum dan tidak ada segmen yang dapat
  /// dicabut tanpa membuat tertanam di bawah minimum.
  tidakBisaCabut,

  /// Tertanam sudah di bawah minimum SEBELUM TM ini — periksa sounding.
  tertanamKurang,
}

class PeringatanCor {
  const PeringatanCor(this.jenis, {required this.setelahM3, required this.tertanamM});

  final JenisPeringatan jenis;
  final double setelahM3;
  final double tertanamM;
}

class RencanaTm {
  const RencanaTm({
    required this.potong,
    required this.peringatan,
    required this.tertanamAkhirM,
    required this.kedalamanBetonAkhirM,
    required this.segmenSisa,
    required this.cutOffTercapai,
  });

  final List<SaranPotong> potong;
  final List<PeringatanCor> peringatan;
  final double tertanamAkhirM;
  final double kedalamanBetonAkhirM;

  /// Bawah → atas.
  final List<Segmen> segmenSisa;
  final bool cutOffTercapai;
}

/// Rencana untuk SATU TM yang akan dicor.
///
/// * [ujungBawahM] — kedalaman ujung bawah tremie dari GS SEKARANG.
/// * [segmen] — segmen terpasang, urut BAWAH → ATAS.
/// * [kedalamanBetonM] — kedalaman muka beton sebelum TM ini (dasar lubang
///   bila TM pertama).
/// * [rasio] — rasio overbreak (1,0 = teoritis); pakai rata-rata TM yang
///   sudah disounding bila ada.
RencanaTm rencanakanTm({
  required int diameterMm,
  required double ujungBawahM,
  required List<Segmen> segmen,
  required double kedalamanBetonM,
  required double kedalamanCutOffM,
  required double volumeM3,
  double rasio = 1.0,
  BatasTertanam batas = const BatasTertanam(),
  double langkahM3 = 0.05,
}) {
  final naik = naikPerM3(diameterMm, rasio: rasio);
  var seg = List<Segmen>.of(segmen);
  var bawah = ujungBawahM;
  final potong = <SaranPotong>[];
  final peringatan = <PeringatanCor>[];

  double beton(double v) => math.max(kedalamanCutOffM, kedalamanBetonM - v * naik);

  final awal = bawah - beton(0);
  if (awal < batas.minimumM - 1e-9) {
    peringatan.add(PeringatanCor(JenisPeringatan.tertanamKurang, setelahM3: 0, tertanamM: _r2(awal)));
  }

  var v = 0.0;
  var macet = false;
  while (v < volumeM3 - 1e-9) {
    final v2 = math.min(volumeM3, v + langkahM3);
    final t2 = bawah - beton(v2);
    if (t2 > batas.maksimumM + 1e-9 && !macet) {
      final tKini = bawah - beton(v);
      final pilih = pilihCabut(seg, tKini, batas);
      if (pilih.isEmpty) {
        peringatan.add(PeringatanCor(JenisPeringatan.tidakBisaCabut, setelahM3: _r2(v), tertanamM: _r2(tKini)));
        macet = true; // satu peringatan cukup; lanjutkan tanpa cabut
      } else {
        final total = pilih.fold(0.0, (a, s) => a + s.panjangM);
        potong.add(SaranPotong(
          setelahM3: _r2(v),
          cabut: pilih,
          tertanamSebelumM: _r2(tKini),
          tertanamSesudahM: _r2(tKini - total),
        ));
        seg = seg.sublist(0, seg.length - pilih.length);
        bawah -= total;
        continue;
      }
    }
    v = v2;
    if (beton(v) <= kedalamanCutOffM + 1e-9) break;
  }

  final akhir = beton(volumeM3);
  return RencanaTm(
    potong: potong,
    peringatan: peringatan,
    tertanamAkhirM: _r2(bawah - akhir),
    kedalamanBetonAkhirM: _r2(akhir),
    segmenSisa: seg,
    cutOffTercapai: akhir <= kedalamanCutOffM + 1e-9,
  );
}

/// Segmen yang disarankan dicabut SEKARANG, dari [tertanamM] yang terukur.
///
/// Dari ATAS, sebanyak mungkin selama tertanam sesudahnya ≥ sasaran;
/// bila sasaran tidak tercapai satu segmen pun, ≥ minimum. Segmen paling
/// bawah tidak pernah dicabut. Kosong = jangan cabut apa pun.
List<Segmen> pilihCabut(List<Segmen> segmen, double tertanamM, BatasTertanam batas) {
  for (final ambang in [batas.sasaranM, batas.minimumM]) {
    var total = 0.0;
    final pilih = <Segmen>[];
    for (final s in segmen.skip(1).toList().reversed) {
      if (tertanamM - (total + s.panjangM) < ambang - 1e-9) break;
      total += s.panjangM;
      pilih.add(s);
    }
    if (pilih.isNotEmpty) return pilih;
  }
  return const [];
}

double _r2(double x) => (x * 100).roundToDouble() / 100;
