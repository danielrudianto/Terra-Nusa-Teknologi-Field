/// Mendiamkan pengingat log bor SAMPAI BESOK PAGI.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA ADA — Daniel, 19 Oktober 2026
/// ──────────────────────────────────────────────────────────────────────────
///
///     "tiap kali orang nge log bor, suka kelupaan, kayanya butuh lebih
///      annoying deh bang alarm nya ... terus tambahain opsi untuk silent
///      notification until tomorrow, takutnya istirahat apa gimana kan?"
///
/// Pengingat yang dibuat lebih sering TANPA jalan keluar akan dimatikan
/// orang — bukan pengingatnya, melainkan seluruh notifikasi aplikasinya,
/// lewat setelan Android, diam-diam, dan selamanya. Sesudah itu tidak ada
/// yang tahu ia sudah tidak pernah berbunyi lagi.
///
/// Jadi makin berisiknya alarm justru menuntut jalan keluar yang sah: satu
/// ketukan yang mendiamkannya sampai pagi, dan yang MENYALA SENDIRI besok
/// tanpa perlu diingat siapa pun.
///
/// Yang didiamkan hanya pengingat log bor. Pengingat TM dan sounding sesudah
/// tuang tidak ikut: keduanya menyangkut beton yang sedang mengeras, dan itu
/// tidak mengenal jam istirahat.
library;

import 'dart:convert';

/// Penundaan pengingat log bor sampai jam tertentu.
class DrillSnooze {
  const DrillSnooze({required this.until});

  /// Sesudah jam ini, pengingatnya kembali berbunyi.
  final DateTime until;

  /// Jam bangun pengingatnya, besok pagi.
  ///
  /// Tujuh pagi, bukan jam kerja kantor: rig sudah menyala sebelum itu, dan
  /// pengingat yang baru hidup pukul delapan melewatkan satu jam pertama —
  /// jam yang justru paling sering terlupakan karena orang masih sibuk
  /// menyiapkan alat.
  static const jamBangun = 7;

  /// Besok pukul [jamBangun], dihitung dari [sekarang].
  ///
  /// SELALU besok, bahkan bila sekarang pukul tiga pagi. Yang menekannya
  /// dini hari bermaksud "jangan ganggu saya sampai hari kerja berikutnya",
  /// bukan "bangunkan saya empat jam lagi".
  static DateTime sampaiBesok(DateTime sekarang) {
    final besok = DateTime(sekarang.year, sekarang.month, sekarang.day + 1);
    return DateTime(besok.year, besok.month, besok.day, jamBangun);
  }

  /// Sedang didiamkan pada [sekarang]?
  bool menunda(DateTime sekarang) => sekarang.isBefore(until);

  String encode() => jsonEncode({'until': until.toIso8601String()});

  static DrillSnooze? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      final until = DateTime.tryParse('${m['until']}');
      if (until == null) return null;
      return DrillSnooze(until: until);
    } catch (_) {
      return null;
    }
  }
}
