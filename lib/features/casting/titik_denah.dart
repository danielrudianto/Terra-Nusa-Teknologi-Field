import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pile_point_data.dart';

/// DENAH TITIK — gambar berskala keadaan seluruh titik satu proyek.
///
/// DIMINTA DANIEL, 19 Oktober 2026: "titik mana yang sudah, titik mana yang
/// belum, titik rencana yang mana aja — biru = sudah bor & cor, rencana =
/// abu, merah sudah dibor", "dengan menggunakan koordinat yang kita udah
/// punya", "baik di HP ataupun di web".
///
/// ATURANNYA SAMA DENGAN WEB (`helpers/titik-denah.helper.ts`). Dua denah
/// yang bentuknya berbeda untuk proyek yang sama tidak dapat dibandingkan,
/// dan yang memegang HP di lapangan membandingkannya dengan layar kantor
/// lewat telepon. Bila salah satu diubah, yang lain ikut.
///
/// TIGA HAL YANG MASING-MASING MERUSAK DENAHNYA TANPA BERSUARA:
///
///   * SKALA X DAN Y HARUS SAMA. Direntangkan masing-masing supaya penuh
///     kotaknya, titik yang berjajar 3 m × 30 m tampak seperti kisi bujur
///     sangkar, dan jarak di gambar berhenti berarti;
///
///   * SUMBU Y TERBALIK. Y survei bertambah ke UTARA (ke atas), y kanvas
///     bertambah ke BAWAH. Digambar apa adanya, denahnya tercermin — masih
///     tampak "benar", dan justru itu sebabnya lolos sampai ke lapangan;
///
///   * TITIK TANPA KOORDINAT TIDAK PUNYA TEMPAT. Dijadikan 0, ia mendarat
///     di pangkal koordinat lalu MENGECILKAN seluruh denah sampai titik
///     yang sebenarnya menggumpal jadi satu. Dikeluarkan, lalu DIHITUNG,
///     supaya layarnya dapat menyebut ada berapa yang tidak tergambar.

/// Keadaan satu titik di denah — lima tingkat, sama dengan web.
enum KeadaanTitik { belumBor, sedangBor, sudahBor, sedangCor, sudahCor }

/// Padanan `FieldPilePoint.stage` ke keadaan denah.
///
/// `berjalan` = log cor masih terbuka; `selesai` = log cornya sudah ditutup
/// tetapi belum tentu sudah tersinkron. Keduanya menyatakan lubang yang
/// SUDAH dibor, jadi ia tidak boleh jatuh ke `belumBor` hanya karena
/// statusnya belum pulang dari server.
KeadaanTitik keadaanTitik(FieldPilePoint p) {
  switch (p.stage) {
    case 'berjalan':
      return KeadaanTitik.sedangCor;
    case 'selesai':
    case 'sudah_cor':
      return KeadaanTitik.sudahCor;
    case 'sudah_bor':
      return KeadaanTitik.sudahBor;
    case 'sedang_bor':
      return KeadaanTitik.sedangBor;
    default:
      return KeadaanTitik.belumBor;
  }
}

/// WARNA SESUAI PERMINTAAN, dan yang SEDANG dikerjakan digambar BERONGGA.
///
/// "sedang dicor" tidak boleh berwujud sama dengan "sudah dicor": satu
/// masih dapat berubah hari ini, satu sudah selesai, dan denah ini dipakai
/// memutuskan rig besok berdiri di mana. Bentuk, bukan hanya warna — ada
/// yang tidak dapat membedakan merah dan abu-abu.
///
/// ANGKA WARNANYA SAMA DENGAN WEB (`GAYA_KEADAAN`).
class GayaKeadaan {
  const GayaKeadaan(this.isi, this.garis);

  /// `null` = berongga.
  final Color? isi;
  final Color garis;
}

const gayaKeadaan = <KeadaanTitik, GayaKeadaan>{
  KeadaanTitik.belumBor: GayaKeadaan(Color(0xFFD9DCE1), Color(0xFF9AA1AC)),
  KeadaanTitik.sedangBor: GayaKeadaan(null, Color(0xFFC62828)),
  KeadaanTitik.sudahBor: GayaKeadaan(Color(0xFFC62828), Color(0xFF8E1F1F)),
  KeadaanTitik.sedangCor: GayaKeadaan(null, Color(0xFF1565C0)),
  KeadaanTitik.sudahCor: GayaKeadaan(Color(0xFF1565C0), Color(0xFF0D3F7A)),
};

/// CINCIN "LEWAT TOLERANSI" TIDAK ADA DI HP, dan itu disengaja.
///
/// Toleransi simpangan adalah angka PROYEK (`toleranceMm`), dan model titik
/// di HP tidak membawanya. Menganggapnya nol akan menyalakan tanda "lewat
/// toleransi" pada setiap titik yang simpangannya bukan nol — yaitu
/// hampir seluruhnya — dan tanda yang menyala di mana-mana berhenti dibaca.
/// Garis rencana→aktualnya tetap digambar, jadi besar simpangan tetap
/// terlihat; yang menilai lulus atau tidak ada di web, tempat angka
/// toleransinya ada.
///
/// Satu titik, sudah dalam satuan gambar.
class TitikDenah {
  const TitikDenah({
    required this.id,
    required this.kode,
    required this.keadaan,
    required this.posisi,
    this.rencana,
  });

  final int? id;
  final String kode;
  final KeadaanTitik keadaan;

  /// Yang digambar: AKTUAL bila ada, kalau tidak rencana.
  final Offset posisi;

  /// Posisi rencana, hanya bila aktualnya ada dan berbeda.
  final Offset? rencana;
}

class Denah {
  const Denah({
    required this.lebar,
    required this.tinggi,
    required this.titik,
    required this.tanpaKoordinat,
    required this.batangSkala,
    required this.meterBatang,
    required this.hitungan,
  });

  final double lebar;
  final double tinggi;
  final List<TitikDenah> titik;

  /// Titik yang koordinatnya belum diisi — tidak tergambar.
  final int tanpaKoordinat;

  /// Panjang batang skala dalam satuan gambar, dan artinya dalam meter.
  final double batangSkala;
  final double meterBatang;

  final Map<KeadaanTitik, int> hitungan;
}

/// Batang skala yang angkanya BULAT — 1, 2, 5, 10, 20, 50 m dan seterusnya.
///
/// Batang "37,4 m" tidak dapat dipakai menakar jarak; yang membaca gambar
/// teknik membandingkan dengan angka bulat.
double meterBulat(double kasar) {
  if (!kasar.isFinite || kasar <= 0) return 1;
  final pangkat = math.pow(10, (math.log(kasar) / math.ln10).floor()).toDouble();
  final sisa = kasar / pangkat;
  final pilih = sisa >= 5
      ? 5.0
      : sisa >= 2
          ? 2.0
          : 1.0;
  return pilih * pangkat;
}

/// Susun denah dalam kotak [lebar] × [tinggi] satuan gambar.
///
/// `null` bila TIDAK ADA satu pun titik berkoordinat: layarnya harus
/// mengatakannya dengan kata-kata, bukan menggambar kotak kosong yang
/// terbaca seperti gambar yang gagal dimuat.
Denah? susunDenah(
  List<FieldPilePoint> titik, {
  double lebar = 1000,
  double tinggi = 700,
  double tepi = 28,
}) {
  final hitungan = {for (final k in KeadaanTitik.values) k: 0};
  final mentah = <({
    int? id,
    String kode,
    KeadaanTitik keadaan,
    double xm,
    double ym,
    double? xmRencana,
    double? ymRencana,
  })>[];
  var tanpaKoordinat = 0;

  for (final p in titik) {
    final keadaan = keadaanTitik(p);
    hitungan[keadaan] = hitungan[keadaan]! + 1;

    final adaAktual = p.actualX != null && p.actualY != null;
    final adaRencana = p.designX != null && p.designY != null;
    if (!adaAktual && !adaRencana) {
      tanpaKoordinat++;
      continue;
    }
    mentah.add((
      id: p.serverId,
      kode: p.code,
      keadaan: keadaan,
      xm: adaAktual ? p.actualX! : p.designX!,
      ym: adaAktual ? p.actualY! : p.designY!,
      // Garis ke rencana hanya bila AKTUALNYA ada: tanpa aktual, yang
      // tergambar ITU rencananya, dan garis ke dirinya sendiri tidak
      // menyatakan apa pun.
      xmRencana: adaAktual && adaRencana ? p.designX : null,
      ymRencana: adaAktual && adaRencana ? p.designY : null,
    ));
  }

  if (mentah.isEmpty) return null;

  final xs = [for (final m in mentah) m.xm];
  final ys = [for (final m in mentah) m.ym];
  var xMin = xs.reduce(math.min);
  var xMaks = xs.reduce(math.max);
  var yMin = ys.reduce(math.min);
  var yMaks = ys.reduce(math.max);

  // Satu titik — atau seluruhnya pada satu garis — membuat salah satu
  // rentangnya nol, dan pembagian dengan nol membuat seluruh denah lenyap.
  //
  // Rentang semunya dibentangkan SETENGAH KE TIAP SISI, bukan ditambahkan
  // di satu sisi: titik tunggal yang mendarat di tepi kiri kotak terbaca
  // sebagai titik yang koordinatnya ada di pojok tapak, padahal yang
  // sebenarnya terjadi adalah tidak ada titik kedua untuk dibandingkan.
  if (xMaks == xMin) {
    xMin -= 0.5;
    xMaks += 0.5;
  }
  if (yMaks == yMin) {
    yMin -= 0.5;
    yMaks += 0.5;
  }
  final bentangX = xMaks - xMin;
  final bentangY = yMaks - yMin;

  final ruangX = math.max(1.0, lebar - 2 * tepi);
  final ruangY = math.max(1.0, tinggi - 2 * tepi);

  // SKALA TUNGGAL — yang paling mengikat dari kedua sumbu.
  final satuanPerMeter = math.min(ruangX / bentangX, ruangY / bentangY);

  final geserX = (lebar - bentangX * satuanPerMeter) / 2;
  final geserY = (tinggi - bentangY * satuanPerMeter) / 2;

  double keX(double xm) => geserX + (xm - xMin) * satuanPerMeter;
  // Y DIBALIK: y kanvas terbesar untuk Y lapangan terkecil.
  double keY(double ym) => tinggi - geserY - (ym - yMin) * satuanPerMeter;

  final meter = meterBulat((ruangX / 4) / satuanPerMeter);

  return Denah(
    lebar: lebar,
    tinggi: tinggi,
    titik: [
      for (final m in mentah)
        TitikDenah(
          id: m.id,
          kode: m.kode,
          keadaan: m.keadaan,
          posisi: Offset(keX(m.xm), keY(m.ym)),
          rencana: m.xmRencana == null || m.ymRencana == null
              ? null
              : Offset(keX(m.xmRencana!), keY(m.ymRencana!)),
        ),
    ],
    tanpaKoordinat: tanpaKoordinat,
    batangSkala: meter * satuanPerMeter,
    meterBatang: meter,
    hitungan: hitungan,
  );
}
