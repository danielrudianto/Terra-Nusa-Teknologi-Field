import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/util/gs_check.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/terra_banner.dart';
import 'level_reference.dart';

/// Penjaga GS yang diketik — dipakai SEMUA dialog yang meminta GS (IPL,
/// "Tandai sudah dibor", konfirmasi GS sebelum bor, dan "Selesai bor").
///
/// Diletakkan PALING ATAS isi dialog. Peringatan lamanya satu baris kecil di
/// bawah isian; di HP dengan huruf diperbesar (HP pak Panji) baris itu
/// terdorong keluar layar dan GS 6.819 lolos ke IPL. Lihat `gs_check.dart`.
class GsGuardBanner extends StatelessWidget {
  const GsGuardBanner({
    super.key,
    required this.typed,
    required this.design,
    required this.cutOffLevel,
    required this.onUse,
  });

  final double? typed;
  final double? design;
  final double? cutOffLevel;

  /// Mengganti isian dengan tebakan angka yang dimaksud.
  final ValueChanged<double> onUse;

  @override
  Widget build(BuildContext context) {
    final v = typed;
    final ref = gsReference(design: design, cutOffLevel: cutOffLevel);
    if (v == null || ref == null) return const SizedBox.shrink();
    final l = t(context);
    final refText = gsReferenceText(context, design: design, cutOffLevel: cutOffLevel);
    if (gsImpossible(v, ref)) {
      final s = gsSuggestion(v, ref);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.report_outlined,
            title: l.gsImpossibleTitle(formatElevation(v, decimals: 3)),
            body: l.gsImpossibleBody(gsSigned(v - ref), refText),
          ),
          // Tombol di BAWAH banner, selebar dialog — bukan di kanannya: dengan
          // huruf besar, tombol di samping menjepit kalimatnya jadi satu kata
          // per baris.
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: () => onUse(s),
                icon: const Icon(Icons.auto_fix_high),
                label: Text(l.gsUseSuggestion(formatElevation(s, decimals: 3))),
              ),
            ),
        ],
      );
    }
    if (gsNeedsConfirm(v, ref)) {
      return TerraBanner(
        kind: BannerKind.warning,
        title: l.gsFarTitle(gsSigned(v - ref), refText),
        body: l.gsFarBody,
      );
    }
    return const SizedBox.shrink();
  }
}

/// `true` bila GS yang diketik TIDAK BOLEH disimpan (lebih dari 10 m dari
/// acuan). Dipakai untuk mematikan tombol Simpan — alasannya banner di atas.
bool gsRefused(double? typed, {double? design, double? cutOffLevel}) =>
    typed != null && gsImpossible(typed, gsReference(design: design, cutOffLevel: cutOffLevel));

/// Dipanggil saat Simpan. `false` = jangan disimpan: mustahil, atau jauh dan
/// mandornya memilih memeriksa lagi. Jawaban "tutup dialog" dihitung TIDAK.
Future<bool> gsConfirmIfFar(
  BuildContext context, {
  required double typed,
  double? design,
  double? cutOffLevel,
}) async {
  final ref = gsReference(design: design, cutOffLevel: cutOffLevel);
  if (ref == null) return true;
  if (gsImpossible(typed, ref)) return false;
  if (!gsNeedsConfirm(typed, ref)) return true;
  final l = t(context);
  return askConfirm(
    context,
    title: l.gsConfirmTitle,
    body: l.gsConfirmBody(
      formatElevation(typed, decimals: 3),
      gsSigned(typed - ref),
      gsReferenceText(context, design: design, cutOffLevel: cutOffLevel),
    ),
    confirmLabel: l.gsConfirmYes,
    cancelLabel: l.gsConfirmNo,
    icon: Icons.warning_amber_rounded,
  );
}

/// "GS desain (+681,741)" atau "COL (+680,500)" — acuan yang benar-benar dipakai.
String gsReferenceText(BuildContext context, {double? design, double? cutOffLevel}) {
  final ref = gsReference(design: design, cutOffLevel: cutOffLevel)!;
  final l = t(context);
  final text = formatElevation(ref, decimals: 3);
  return design != null && ref == design ? l.gsRefDesign(text) : l.gsRefCol(text);
}

/// "+0,120" / "−0,050" / "±0,000" — tandanya selalu ditulis.
String gsSigned(double v) {
  final s = v.abs().toStringAsFixed(3).replaceAll('.', ',');
  return '${v > 0.0005 ? '+' : v < -0.0005 ? '−' : '±'}$s';
}

/// Teks isian untuk tebakan: "681,900" (tanpa "+", seperti yang diketik).
String gsInputText(double v) => v.toStringAsFixed(3).replaceAll('.', ',');
