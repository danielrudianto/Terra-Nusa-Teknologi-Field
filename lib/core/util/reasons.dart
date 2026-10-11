/// Rejection reason from the server (`reason`) as a sentence for the foreman/QS.
///
/// Same codes as `controllers/field_controller.py`. Codes not yet
/// recognized are shown as-is — better to look odd than to be hidden.
/// disembunyikan.
String reasonText(String? code, [String? detail]) {
  final k = switch (code) {
    'TIDAK_VALID' => 'Isi data tidak sah',
    'TIDAK_BERHAK' => 'Akun Anda tidak berhak menyimpan data ini',
    'BUKAN_MILIK' => 'Data ini milik pengguna lain',
    'DIOPER' => 'Log ini sudah dioper ke rekan — perubahan hanya dari HP pemegangnya',
    'SUDAH_DIHAPUS' => 'Data ini sudah dihapus di kantor',
    'SUDAH_DITINJAU' => 'Absen sudah ditinjau kantor — tidak dapat diubah lagi',
    'SUDAH_DIPERIKSA' => 'Log cor sudah diperiksa kantor — tidak dapat diubah lagi',
    'SUDAH_DICOR' => 'Titik ini sudah tercatat dicor',
    'PROYEK_TIDAK_ADA' => 'Proyek tidak ditemukan atau sudah ditutup',
    'PROYEK_TANGGAL_TETAP' => 'Proyek dan tanggal absen tidak dapat diganti setelah terkirim',
    'TANGGAL_DEPAN' => 'Tanggal absen di masa depan — periksa jam HP',
    'ABSEN_SUDAH_ADA' => 'Sudah ada absen Anda untuk proyek dan tanggal ini',
    'WORKER_BELUM_ADA' => 'Menunggu data pekerja baru terkirim lebih dulu',
    'PEKERJA_DIHAPUS' => 'Ada pekerja yang sudah dihapus di kantor',
    // No longer sent by the server since workers became company-wide;
    // kept for items rejected before the change.
    'PEKERJA_BUKAN_KRU' => 'Ada pekerja yang bukan kru Anda',
    'PEKERJA_GANDA' => 'Ada pekerja tercatat dua kali',
    'UUID_BENTROK' => 'Data bentrok dengan data lain — hubungi admin',
    'TITIK_TIDAK_ADA' => 'Titik bor tidak ditemukan atau sudah dihapus',
    'TITIK_TETAP' => 'Titik log cor tidak dapat diganti',
    'COR_SUDAH_ADA' => 'Titik ini sudah punya log cor dari HP lain',
    'MUTU_KOSONG' => "Mutu beton (fc') belum diisi — isi di log cor, atau minta kantor mengisinya di titik/proyek",
    'PEMASOK_TIDAK_ADA' => 'Pemasok beton tidak ditemukan',
    'TM_GANDA' => 'Nomor urut TM ganda',
    'JAM_TM_TERBALIK' => 'Jam selesai TM lebih awal dari jam mulai',
    'SEGMEN_GANDA' => 'Posisi segmen tremie ganda',
    'SEGMEN_TM_ASING' => 'Segmen dicabut setelah TM yang tidak ada',
    'GS_KOSONG' => 'Elevasi GS titik ini belum diisi — isi saat menandai titik dibor',
    'JEDA_TM_ASING' => 'Ada jeda untuk TM yang tidak ada',
    'JAM_JEDA_TERBALIK' => 'Jam jeda tidak masuk akal — periksa jam HP',
    'TREMIE_BOTTOM_SALAH' => 'Tremie bottom harus paling bawah, hanya satu, dan tidak dicabut',
    'SOUNDING_KOSONG' => 'Sounding sesudah TM belum diisi — wajib sebelum selesai cor',
    'LOG_BOR_SUDAH_ADA' => 'Titik ini sudah punya log bor dari HP lain',
    'KEDALAMAN_MUNDUR' => 'Ada bacaan bor yang lebih dangkal dari bacaan sebelumnya',
    'BOR_KOSONG' => 'Log bor belum punya satu pun bacaan kedalaman',
    'ENTRI_GANDA' => 'Ada bacaan bor tercatat dua kali',
    'BERKAS_HILANG' => 'Berkas foto hilang dari HP',
    null => 'Ditolak server',
    _ => code,
  };
  return detail == null || detail.isEmpty ? k : '$k ($detail)';
}

/// Entity name for the screen.
String entityLabel(String entity) => switch (entity) {
      'worker' => 'Pekerja',
      'attendance' => 'Absen',
      'drill_mark' => 'Tanda bor',
      'drill_log' => 'Log bor',
      'casting' => 'Log cor',
      _ => entity,
    };
