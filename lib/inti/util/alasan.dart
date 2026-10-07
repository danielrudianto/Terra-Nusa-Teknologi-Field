/// Sebab penolakan dari server (`reason`) dalam kalimat untuk mandor/QS.
///
/// Kode yang sama dengan `controllers/field_controller.py`. Kode yang belum
/// dikenal ditampilkan apa adanya — lebih baik terlihat aneh daripada
/// disembunyikan.
String kalimatAlasan(String? kode, [String? detail]) {
  final k = switch (kode) {
    'TIDAK_VALID' => 'Isi data tidak sah',
    'TIDAK_BERHAK' => 'Akun Anda tidak berhak menyimpan data ini',
    'BUKAN_MILIK' => 'Data ini milik pengguna lain',
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
    'BERKAS_HILANG' => 'Berkas foto hilang dari HP',
    null => 'Ditolak server',
    _ => kode,
  };
  return detail == null || detail.isEmpty ? k : '$k ($detail)';
}

/// Nama entitas untuk layar.
String namaEntitas(String entitas) => switch (entitas) {
      'worker' => 'Pekerja',
      'attendance' => 'Absen',
      'drill_mark' => 'Tanda bor',
      'casting' => 'Log cor',
      _ => entitas,
    };
