import 'dart:math' as math;

/// Hitungan geometri bored pile — SAMA dengan `hitung_cor` di server
/// (`utils/field_hitung.py`). Di HP untuk ditampilkan saat mengecor; angka
/// yang tercatat tetap hitungan server.
///
/// ELEVASI vs KEDALAMAN
///
/// Gambar kerja memberi ELEVASI (m, naik ke atas): GS (muka tanah titik
/// itu), cut-off (sampai mana beton dicor), tip (dasar rencana). Di lubang,
/// QS mengukur KEDALAMAN dari GS (m, turun ke bawah): kedalaman bor,
/// kedalaman muka beton (sounding). Semua hitungan di bawah memakai
/// kedalaman dari GS; elevasi diubah sekali di [GeometriTitik].

double luasPenampangM2(int diameterMm) {
  final d = diameterMm / 1000.0;
  return math.pi / 4 * d * d;
}

class GeometriTitik {
  const GeometriTitik({
    required this.diameterMm,
    required this.groundLevel,
    required this.cutOffLevel,
    required this.tipLevel,
    this.drilledDepthM,
  });

  final int diameterMm;
  final double groundLevel;
  final double cutOffLevel;
  final double tipLevel;

  /// Kedalaman bor AKTUAL dari GS (ditandai QS). Null = belum dibor.
  final double? drilledDepthM;

  double get luasM2 => luasPenampangM2(diameterMm);

  /// Kedalaman cut-off dari GS — muka beton berhenti di sini.
  double get kedalamanCutOffM => groundLevel - cutOffLevel;

  /// Panjang bor rencana = GS − tip.
  double get panjangBorRencanaM => groundLevel - tipLevel;

  /// Panjang efektif rencana = cut-off − tip.
  double get panjangEfektifRencanaM => cutOffLevel - tipLevel;

  /// Panjang efektif aktual = kedalaman bor aktual − kedalaman cut-off.
  double? get panjangEfektifAktualM => drilledDepthM == null ? null : drilledDepthM! - kedalamanCutOffM;

  double get volumeTeoritisRencanaM3 => luasM2 * panjangEfektifRencanaM;

  double? get volumeTeoritisAktualM3 {
    final p = panjangEfektifAktualM;
    return p == null ? null : luasM2 * p;
  }

  /// Kedalaman dasar lubang yang dipakai menghitung: aktual bila sudah
  /// ditandai, rencana bila belum.
  double get kedalamanDasarM => drilledDepthM ?? panjangBorRencanaM;
}

/// Kenaikan muka beton teoritis per m³ (m/m³), dengan rasio overbreak.
///
/// Rasio 1,15 = lubang 15% lebih besar dari diameter nominal (dinding
/// runtuh / tanah lunak): beton naik lebih pelan dari teori.
double naikPerM3(int diameterMm, {double rasio = 1.0}) =>
    1.0 / (luasPenampangM2(diameterMm) * math.max(rasio, 0.2));

/// Rasio overbreak satu TM dari sounding sebelum & sesudahnya.
/// Null bila tidak terukur (sounding kosong atau tidak naik).
double? rasioOverbreak({
  required int diameterMm,
  required double volumeM3,
  required double? kedalamanSebelumM,
  required double? kedalamanSesudahM,
}) {
  if (kedalamanSebelumM == null || kedalamanSesudahM == null) return null;
  final naik = kedalamanSebelumM - kedalamanSesudahM;
  if (naik <= 0.01) return null;
  return volumeM3 / (luasPenampangM2(diameterMm) * naik);
}
