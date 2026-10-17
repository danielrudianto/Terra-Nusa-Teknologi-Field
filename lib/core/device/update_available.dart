import 'dart:convert';

/// "Ada versi yang lebih baru" — AJAKAN, bukan pemblokiran.
///
/// Dibedakan tajam dari [AppOutdated], yang menggantikan seluruh aplikasi
/// dengan layar "Perbarui app" ketika server MENOLAK versi ini
/// (`FIELD_MIN_APP_VERSION`). Yang ini tidak menghalangi apa pun: kru tetap
/// mencatat seperti biasa, dan hanya diberi tahu.
///
/// Bedanya bukan gaya, melainkan kapan masing-masing aman dipakai. Ambang
/// penolakan baru boleh dinaikkan SESUDAH HP kru benar-benar mendapat
/// APK-nya; dinaikkan lebih awal ia mengunci kru, dan bila itu terjadi di
/// tengah pengecoran, TM sudah di lokasi dan tidak ada yang dapat dicatat.
/// Ajakan ini aman dinyalakan pada detik rilisnya terbit.
///
/// SERVER yang memutuskan ada atau tidaknya; HP hanya menampilkan apa yang
/// dikirimkan. Dengan begitu aturannya dapat diubah lewat `.env` tanpa APK
/// baru — dan memudahkan rilis justru tujuan fitur ini.
class UpdateAvailable {
  const UpdateAvailable({required this.latestVersion, this.downloadUrl});

  /// Versi terbaru yang sudah tersedia, mis. `1.0.6+21`.
  final String latestVersion;

  /// Tempat mengunduhnya. `null` = tidak ada tautan, jadi tombolnya tidak
  /// ditampilkan — tombol yang tidak membuka apa pun lebih buruk daripada
  /// tidak ada tombol.
  final String? downloadUrl;

  /// Membaca blok `device.update` dari jawaban pull.
  ///
  /// Kunci `update` TIDAK DIKIRIM bila tidak ada pembaruan, jadi
  /// ketiadaannya berarti "sudah terbaru" — dan server lama yang belum
  /// mengenal fitur ini menghasilkan `null` juga, bukan galat.
  static UpdateAvailable? fromPull(Object? raw) {
    if (raw is! Map) return null;
    final u = raw['update'];
    if (u is! Map) return null;
    final versi = u['latestVersion']?.toString() ?? '';
    if (versi.isEmpty) return null;
    final tautan = u['downloadUrl']?.toString();
    return UpdateAvailable(
      latestVersion: versi,
      downloadUrl: (tautan == null || tautan.isEmpty) ? null : tautan,
    );
  }

  String encode() => jsonEncode({
        'latestVersion': latestVersion,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
      });

  static UpdateAvailable? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      final versi = m['latestVersion']?.toString() ?? '';
      if (versi.isEmpty) return null;
      return UpdateAvailable(
        latestVersion: versi,
        downloadUrl: m['downloadUrl']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Penundaan ajakan memperbarui: "jangan sekarang", bukan "jangan pernah".
///
/// Disimpan BESERTA versi yang ditunda. Tanpa itu, menunda 1.0.6 ikut
/// menyembunyikan 1.0.7 yang terbit keesokan harinya — dan rilis yang justru
/// penting lewat tanpa seorang pun melihatnya.
class UpdateSnooze {
  const UpdateSnooze({required this.version, required this.until});

  final String version;
  final DateTime until;

  /// Lama penundaan. Delapan jam = satu giliran kerja: yang menundanya di
  /// pagi hari melihatnya lagi besok pagi, bukan lima menit kemudian saat
  /// TM berikutnya datang.
  static const durasi = Duration(hours: 8);

  /// Ajakan untuk [versi] sedang ditunda pada [sekarang]?
  bool menunda(String versi, DateTime sekarang) =>
      versi == version && sekarang.isBefore(until);

  String encode() => jsonEncode({
        'version': version,
        'until': until.toIso8601String(),
      });

  static UpdateSnooze? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      final versi = m['version']?.toString() ?? '';
      final until = DateTime.tryParse('${m['until']}');
      if (versi.isEmpty || until == null) return null;
      return UpdateSnooze(version: versi, until: until);
    } catch (_) {
      return null;
    }
  }
}
