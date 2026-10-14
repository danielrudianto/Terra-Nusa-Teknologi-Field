import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
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
      actualX: parseNumber(xInput.text),
      actualY: parseNumber(yInput.text),
    );
    final batas = toleranceMm;
    final lewat = simpangan != null && batas != null && simpangan > batas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _isian(context, xInput, wajib ? l.actualXRequired : l.actualX)),
            const SizedBox(width: 10),
            Expanded(child: _isian(context, yInput, wajib ? l.actualYRequired : l.actualY)),
          ],
        ),
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
                  ? l.designXYBody(formatMeters(designX, decimals: 3), formatMeters(designY, decimals: 3))
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
        inputFormatters: decimalInput(maxIntDigits: 9, decimals: 3, signed: true),
        decoration: InputDecoration(labelText: label, suffixText: 'm'),
        onChanged: (_) => onChanged(),
      );
}

/// Milimeter bulat, tanpa desimal: toleransi tiang dinyatakan dalam
/// milimeter bulat (75 mm), dan "74,83 mm" membaca lebih tepat daripada
/// alat ukurnya sendiri.
String formatMm(double? v) => v == null ? '—' : '${v.round()} mm';

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
  final nx = parseNumber(x);
  final ny = parseNumber(y);
  if (nx == null || ny == null || nx.abs() > koordinatMaks || ny.abs() > koordinatMaks) {
    return l.actualXYInvalid;
  }
  return null;
}
