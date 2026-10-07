import 'dart:math' as math;

import '../../../inti/util/format.dart';
import 'volume.dart';

/// Keadaan cor SAAT INI, dibaca dari dokumen log cor di HP.
///
/// Tidak ada angka yang disimpan dua kali: panjang tremie terpasang, ujung
/// bawahnya, dan muka beton semuanya diturunkan dari segmen yang dicentang
/// dicabut dan sounding tiap TM. Mengubah satu centang mengubah semuanya
/// dengan sendirinya.
class KeadaanCor {
  KeadaanCor._({
    required this.geometri,
    required this.celahBawahM,
    required this.segmen,
    required this.tm,
  });

  factory KeadaanCor.dari(GeometriTitik geometri, Map<String, Object?> dok) {
    return KeadaanCor._(
      geometri: geometri,
      celahBawahM: keDouble(dok['tremieBottomGapM']) ?? 0.30,
      segmen: [
        for (final s in (dok['tremie'] as List?) ?? const [])
          SegmenCor.dariJson((s as Map).cast<String, Object?>()),
      ]..sort((a, b) => a.posisi.compareTo(b.posisi)),
      tm: [
        for (final t in (dok['trucks'] as List?) ?? const []) TmCatatan.dariJson((t as Map).cast<String, Object?>()),
      ]..sort((a, b) => a.seq.compareTo(b.seq)),
    );
  }

  final GeometriTitik geometri;
  final double celahBawahM;

  /// Urut posisi 1 = PALING BAWAH.
  final List<SegmenCor> segmen;
  final List<TmCatatan> tm;

  /// Segmen yang masih terpasang SETELAH TM ke-[seq] (0 = sebelum TM 1).
  List<SegmenCor> terpasangSetelah(int seq) =>
      [for (final s in segmen) if (s.dicabutSetelahTm == null || s.dicabutSetelahTm! > seq) s];

  double panjangTerpasangSetelah(int seq) => terpasangSetelah(seq).fold(0.0, (a, s) => a + s.panjangM);

  /// Ujung bawah tremie setelah TM ke-[seq]: dasar − celah − yang sudah
  /// dicabut sampai TM itu.
  double ujungBawahSetelah(int seq) {
    final dicabut = segmen
        .where((s) => s.dicabutSetelahTm != null && s.dicabutSetelahTm! <= seq)
        .fold(0.0, (a, s) => a + s.panjangM);
    return geometri.kedalamanDasarM - celahBawahM - dicabut;
  }

  /// Rata-rata rasio overbreak TM yang sudah disounding sebelum & sesudah.
  /// 1,0 bila belum ada. Dibatasi 0,8–2,0: satu sounding yang salah baca
  /// tidak boleh membuat saran berikutnya ngawur.
  double get rasioRataRata {
    final r = <double>[];
    for (final t in tm) {
      final x = rasioOverbreak(
        diameterMm: geometri.diameterMm,
        volumeM3: t.volumeM3,
        kedalamanSebelumM: t.betonSebelumM,
        kedalamanSesudahM: t.betonSesudahM,
      );
      if (x != null) r.add(x);
    }
    if (r.isEmpty) return 1.0;
    final rata = r.reduce((a, b) => a + b) / r.length;
    return rata.clamp(0.8, 2.0);
  }

  /// Muka beton setelah TM ke-[seq]: sounding bila ada, perkiraan bila tidak.
  /// (seq 0 = dasar lubang.) `terukur` false = perkiraan.
  ({double kedalamanM, bool terukur}) betonSetelah(int seq) {
    var kedalaman = geometri.kedalamanDasarM;
    var terukur = true;
    final rasio = rasioRataRata;
    for (final t in tm) {
      if (t.seq > seq) break;
      if (t.betonSebelumM != null) {
        kedalaman = t.betonSebelumM!;
        terukur = true;
      }
      if (t.betonSesudahM != null) {
        kedalaman = t.betonSesudahM!;
        terukur = true;
      } else {
        kedalaman = math.max(
          geometri.kedalamanCutOffM,
          kedalaman - t.volumeM3 * naikPerM3(geometri.diameterMm, rasio: rasio),
        );
        terukur = false;
      }
    }
    return (kedalamanM: kedalaman, terukur: terukur);
  }

  int get seqTerakhir => tm.isEmpty ? 0 : tm.last.seq;

  double get volumeTotalM3 => tm.fold(0.0, (a, t) => a + t.volumeM3);

  /// Panjang tertanam setelah TM ke-[seq].
  double tertanamSetelah(int seq) => ujungBawahSetelah(seq) - betonSetelah(seq).kedalamanM;

  /// Lebih pakai beton terhadap volume teoritis aktual, persen.
  double? get lebihPakaiPersen {
    final teori = geometri.volumeTeoritisAktualM3 ?? geometri.volumeTeoritisRencanaM3;
    if (teori <= 0 || tm.isEmpty) return null;
    return (volumeTotalM3 / teori - 1) * 100;
  }
}

class SegmenCor {
  const SegmenCor({required this.uuid, required this.posisi, required this.panjangM, this.dicabutSetelahTm, this.dicabutPada});

  final String uuid;
  final int posisi;
  final double panjangM;
  final int? dicabutSetelahTm;
  final String? dicabutPada;

  factory SegmenCor.dariJson(Map<String, Object?> j) => SegmenCor(
        uuid: '${j['uuid']}',
        posisi: keInt(j['position']) ?? 0,
        panjangM: keDouble(j['lengthM']) ?? 0,
        dicabutSetelahTm: keInt(j['removedAfterTruckSeq']),
        dicabutPada: j['removedAt']?.toString(),
      );
}

class TmCatatan {
  const TmCatatan({required this.seq, required this.volumeM3, this.betonSebelumM, this.betonSesudahM, this.mulai, this.selesai});

  final int seq;
  final double volumeM3;
  final double? betonSebelumM;
  final double? betonSesudahM;
  final DateTime? mulai;
  final DateTime? selesai;

  factory TmCatatan.dariJson(Map<String, Object?> j) => TmCatatan(
        seq: keInt(j['seq']) ?? 0,
        volumeM3: keDouble(j['volumeM3']) ?? 0,
        betonSebelumM: keDouble(j['concreteDepthBeforeM']),
        betonSesudahM: keDouble(j['concreteDepthAfterM']),
        mulai: j['startAt'] == null ? null : DateTime.tryParse('${j['startAt']}'),
        selesai: j['endAt'] == null ? null : DateTime.tryParse('${j['endAt']}'),
      );
}
