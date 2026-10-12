import 'package:flutter/widgets.dart';

import '../i18n.dart';

/// Rejection reason from the server (`reason`) as a sentence for the foreman/QS.
///
/// Same codes as `controllers/field_controller.py`. The CODES never change —
/// they are the server's contract — only the sentence the screen shows is
/// translated. A code this build does not know is shown as-is: looking odd
/// beats being hidden.
String reasonText(BuildContext context, String? code, [String? detail]) {
  final l = t(context);
  final k = switch (code) {
    'TIDAK_VALID' => l.reasonTidakValid,
    'TIDAK_BERHAK' => l.reasonTidakBerhak,
    'BUKAN_MILIK' => l.reasonBukanMilik,
    'DIOPER' => l.reasonDioper,
    'SUDAH_DIHAPUS' => l.reasonSudahDihapus,
    'SUDAH_DITINJAU' => l.reasonSudahDitinjau,
    'SUDAH_DIPERIKSA' => l.reasonSudahDiperiksa,
    'SUDAH_DICOR' => l.reasonSudahDicor,
    'PROYEK_TIDAK_ADA' => l.reasonProyekTidakAda,
    'PROYEK_TANGGAL_TETAP' => l.reasonProyekTanggalTetap,
    'TANGGAL_DEPAN' => l.reasonTanggalDepan,
    'ABSEN_SUDAH_ADA' => l.reasonAbsenSudahAda,
    'WORKER_BELUM_ADA' => l.reasonWorkerBelumAda,
    'PEKERJA_DIHAPUS' => l.reasonPekerjaDihapus,
    'PEKERJA_BUKAN_KRU' => l.reasonPekerjaBukanKru,
    'PEKERJA_GANDA' => l.reasonPekerjaGanda,
    'UUID_BENTROK' => l.reasonUuidBentrok,
    'TITIK_TIDAK_ADA' => l.reasonTitikTidakAda,
    'TITIK_TETAP' => l.reasonTitikTetap,
    'COR_SUDAH_ADA' => l.reasonCorSudahAda,
    'MUTU_KOSONG' => l.reasonMutuKosong,
    'PEMASOK_TIDAK_ADA' => l.reasonPemasokTidakAda,
    'TM_GANDA' => l.reasonTmGanda,
    'JAM_TM_TERBALIK' => l.reasonJamTmTerbalik,
    'SEGMEN_GANDA' => l.reasonSegmenGanda,
    'SEGMEN_TM_ASING' => l.reasonSegmenTmAsing,
    'GS_KOSONG' => l.reasonGsKosong,
    'JEDA_TM_ASING' => l.reasonJedaTmAsing,
    'JAM_JEDA_TERBALIK' => l.reasonJamJedaTerbalik,
    'TREMIE_BOTTOM_SALAH' => l.reasonTremieBottomSalah,
    'SOUNDING_KOSONG' => l.reasonSoundingKosong,
    'LOG_BOR_SUDAH_ADA' => l.reasonLogBorSudahAda,
    'KEDALAMAN_MUNDUR' => l.reasonKedalamanMundur,
    'BOR_KOSONG' => l.reasonBorKosong,
    'ENTRI_GANDA' => l.reasonEntriGanda,
    'BERKAS_HILANG' => l.reasonBerkasHilang,
    null => l.rejectedByServer,
    _ => code,
  };
  return detail == null || detail.isEmpty ? k : l.reasonWithDetail(k, detail);
}

/// Entity name for the screen.
String entityLabel(BuildContext context, String entity) => switch (entity) {
      'worker' => t(context).entityWorker,
      'attendance' => t(context).entityAttendance,
      'drill_mark' => t(context).entityDrillMark,
      'drill_log' => t(context).entityDrillLog,
      'casting' => t(context).entityCasting,
      _ => entity,
    };
