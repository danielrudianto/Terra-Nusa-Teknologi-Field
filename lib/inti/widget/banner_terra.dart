import 'package:flutter/material.dart';

import '../tema/token_warna.dart';
import '../tema/ukuran.dart';

enum JenisBanner { info, awas, bahaya, ok }

/// Banner TerraBot: ikon di kiri, judul tebal, lalu kalimat penjelas.
///
/// Meniru `.pou-banner` / `.plc-banner` di web. INILAH pengganti hint kecil
/// di bawah field — semua penjelasan yang perlu dibaca masuk ke sini, dengan
/// huruf yang terbaca di HP yang dipegang sejauh lengan.
class BannerTerra extends StatelessWidget {
  const BannerTerra({
    super.key,
    required this.jenis,
    required this.judul,
    this.isi,
    this.ikon,
    this.aksi,
  });

  final JenisBanner jenis;
  final String judul;
  final String? isi;
  final IconData? ikon;

  /// Tombol opsional di kanan (mis. "Coba lagi", "Masuk").
  final Widget? aksi;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final (latar, depan, ikonBawaan) = switch (jenis) {
      JenisBanner.info => (w.brandSoft, w.brandStrong, Icons.info_outline),
      JenisBanner.awas => (w.warnBg, w.warnFg, Icons.warning_amber_rounded),
      JenisBanner.bahaya => (w.badBg, w.badFg, Icons.error_outline),
      JenisBanner.ok => (w.okBg, w.okFg, Icons.check_circle_outline),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(Ukuran.radiusBanner),
        border: Border.all(color: depan.withValues(alpha: 0.45), width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(ikon ?? ikonBawaan, size: 22, color: depan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: depan),
                ),
                if (isi != null && isi!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(isi!, style: TextStyle(fontSize: 14, height: 1.4, color: depan)),
                ],
              ],
            ),
          ),
          if (aksi != null) ...[const SizedBox(width: 8), aksi!],
        ],
      ),
    );
  }
}
