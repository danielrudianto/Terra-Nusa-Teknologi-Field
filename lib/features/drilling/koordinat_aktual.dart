import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';

/// X/Y AKTUAL — posisi pusat lubang, diukur SESUDAH pengeborannya selesai.
///
/// DIMINTA DANIEL, 14 Oktober 2026, sesudah satu revisi: "titik X dan Y
/// aktual itu baru bisa diwajibkan setelah pengeboran selesai, bukan pas
/// awal. kalau GS udah bener sebelum bor mulai."
///
/// Karena itu isian ini ada di DUA dialog yang menutup pengeboran — "Tandai
/// sudah dibor" dan "Selesai bor" — dan tidak ada sama sekali di dialog yang
/// memulainya. Keduanya memakai widget yang sama supaya aturan dan
/// peringatannya tidak dapat menua sendiri-sendiri.

/// Batas nilai koordinat, sama dengan `_KOORD` di server.
const koordinatMaks = 999999999.0;

/// Simpangan antara posisi rencana dan posisi aktual, dalam MILIMETER.
///
/// `null` bila salah satu dari empat angkanya belum ada — bukan nol. Titik
/// yang koordinat rencananya belum pernah diisi akan terbaca "simpangan 0
/// mm", yaitu tepat di rencana, padahal yang benar "tidak diketahui". Angka
/// itu lalu dibandingkan dengan toleransi dan lulus.
double? simpanganMm({
  double? designX,
  double? designY,
  double? actualX,
  double? actualY,
}) {
  if (designX == null || designY == null || actualX == null || actualY == null) {
    return null;
  }
  final dx = actualX - designX;
  final dy = actualY - designY;
  return math.sqrt(dx * dx + dy * dy) * 1000;
}

/// Dua isian koordinat beserta peringatan simpangannya.
///
/// PENGENDALINYA MILIK INDUKNYA, seperti isian GS di sebelahnya: dibuang di
/// sini sementara dialognya masih beranimasi keluar, aplikasinya tutup
/// sendiri ('_dependents.isEmpty').
class KoordinatAktualFields extends StatelessWidget {
  const KoordinatAktualFields({
    super.key,
    required this.xInput,
    required this.yInput,
    required this.wajib,
    required this.designX,
    required this.designY,
    required this.toleranceMm,
    required this.onChanged,
  });

  final TextEditingController xInput;
  final TextEditingController yInput;
  final bool wajib;
  final double? designX;
  final double? designY;

  /// Toleransi simpangan proyek. `null` = tidak diketahui, dan ketika tidak
  /// diketahui tidak ada yang dinyatakan di luar batas: menganggapnya nol
  /// akan menyalakan peringatan merah pada setiap titik.
  final double? toleranceMm;

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final simpangan = simpanganMm(
      designX: designX,
      designY: designY,
      actualX: parseKoordinat(xInput.text),
      actualY: parseKoordinat(yInput.text),
    );
    final batas = toleranceMm;
    final lewat = simpangan != null && batas != null && simpangan > batas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        // BERTUMPUK, bukan berdampingan.
        //
        // ROYAN, 21 Okt 2026: koordinatnya terpotong di kedua ujung dan ia
        // tidak dapat membaca ulang apa yang baru diketiknya. Koordinat grid
        // lengkap berbunyi "9.224.128,858 m" — tiga belas huruf. Dua isian
        // berdampingan pada lebar dialog di HP memberi masing-masing sekitar
        // separuhnya, dan angka yang terpotong pada isian koordinat lebih
        // buruk daripada isian yang sempit: satu digit yang tidak terlihat
        // menggeser titiknya satu kilometer.
        _isian(context, xInput, wajib ? l.actualXRequired : l.actualX),
        const SizedBox(height: 10),
        _isian(context, yInput, wajib ? l.actualYRequired : l.actualY),
        // Koordinat rencana ditampilkan sebagai acuan. Tanpa itu yang
        // mengetik tidak punya pembanding, dan angka yang tertukar X dengan
        // Y hanya terlihat sebagai simpangan besar tanpa sebab yang jelas.
        if (designX != null && designY != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TerraBanner(
              kind: lewat ? BannerKind.danger : BannerKind.info,
              title: lewat ? l.deviationOverTitle(formatMm(simpangan)) : l.designXYTitle,
              body: simpangan == null
                  ? l.designXYBody(formatKoordinat(designX), formatKoordinat(designY))
                  : lewat
                      ? l.deviationOverBody(formatMm(batas))
                      : l.deviationBody(formatMm(simpangan), formatMm(batas)),
            ),
          ),
      ],
    );
  }

  Widget _isian(BuildContext context, TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        // Pemisah ribuan SAMBIL DIKETIK — lihat `KoordinatInputFormatter`.
        inputFormatters: koordinatInput(),
        decoration: InputDecoration(labelText: label, suffixText: 'm'),
        onChanged: (_) => onChanged(),
      );
}

/// Milimeter bulat, tanpa desimal: toleransi tiang dinyatakan dalam
/// milimeter bulat (75 mm), dan "74,83 mm" membaca lebih tepat daripada
/// alat ukurnya sendiri.
String formatMm(double? v) => v == null ? '—' : '${v.round()} mm';

/// PERINGATAN KERAS sebelum menyimpan koordinat yang melewati toleransi.
///
/// DIMINTA DANIEL, 20 Oktober 2026: "bantu kasih warning keras kalau
/// simpangan terlalu jauh pada saat input X dan Y, kan batas maximum 75mm".
///
/// Banner merah di bawah isiannya sudah ada, tetapi banner tidak menghentikan
/// siapa pun: yang sedang berdiri di samping rig mengetik dua angka lalu
/// menekan Simpan tanpa membaca apa pun di antaranya. Simpangan yang lewat
/// toleransi adalah temuan yang harus ditangani SEBELUM lubangnya dicor —
/// sesudah dicor, satu-satunya pilihan yang tersisa adalah perkuatan, dan
/// itu bukan keputusan operator HP.
///
/// Karena itu pintunya DIPALANG, bukan diberi tanda: memerlukan satu
/// ketukan sadar pada tombol yang menyebutkan angkanya. Tombol lanjutnya
/// ditulis "Simpan apa adanya" dan ditaruh di posisi yang BUKAN bawaan —
/// yang menekan dua kali karena terburu-buru akan menekan "Periksa lagi".
///
/// Mengembalikan `true` bila boleh dilanjutkan.
Future<bool> lanjutkanMeskiSimpang(
  BuildContext context, {
  required double? designX,
  required double? designY,
  required String xText,
  required String yText,
  required double? toleranceMm,
}) async {
  final simpangan = simpanganMm(
    designX: designX,
    designY: designY,
    actualX: parseKoordinat(xText),
    actualY: parseKoordinat(yText),
  );
  final batas = toleranceMm;
  // Toleransi yang tidak diketahui TIDAK menghalangi apa pun: menganggapnya
  // nol akan memalang setiap titik yang simpangannya bukan nol, yaitu
  // hampir seluruhnya, dan palang yang selalu muncul berhenti dibaca.
  if (simpangan == null || batas == null || simpangan <= batas) return true;

  final l = t(context);
  final w = context.colors;
  final boleh = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: w.badFg, size: 34),
      title: Text(l.deviationStopTitle(formatMm(simpangan))),
      content: Text(
        l.deviationStopBody(
          formatMm(batas),
          formatMm(simpangan - batas),
        ),
      ),
      actions: [
        // "Simpan apa adanya" DI KIRI dan tidak ditonjolkan; "Periksa lagi"
        // di kanan sebagai tombol utama.
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.deviationStopSave, style: TextStyle(color: w.muted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.deviationStopRecheck),
        ),
      ],
    ),
  );
  return boleh ?? false;
}

/// Pesan galat bila isian koordinat belum sah, atau `null` bila sudah.
///
/// NOL ADALAH KOORDINAT YANG SAH — titik acuan grid lokal. Diperiksa dengan
/// kebenaran nilainya alih-alih kosong/tidak, titik tepat di acuannya akan
/// ditolak terus tanpa sebab yang dapat dibaca.
String? koordinatBelumSah(BuildContext context, String xText, String yText, {required bool wajib}) {
  final l = t(context);
  final x = xText.trim();
  final y = yText.trim();
  if (x.isEmpty && y.isEmpty) return wajib ? l.actualXYRequiredMsg : null;
  // Setengah terisi selalu ditolak, juga ketika tidak wajib: satu koordinat
  // tanpa pasangannya tidak dapat dipakai menghitung apa pun, dan yang
  // tersimpan sebelah akan terbaca sebagai data yang ada.
  if (x.isEmpty || y.isEmpty) return l.actualXYBothMsg;
  final nx = parseKoordinat(x);
  final ny = parseKoordinat(y);
  if (nx == null || ny == null || nx.abs() > koordinatMaks || ny.abs() > koordinatMaks) {
    return l.actualXYInvalid;
  }
  return null;
}
