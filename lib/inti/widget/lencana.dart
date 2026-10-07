import 'package:flutter/material.dart';

import '../tema/token_warna.dart';

/// Lencana kecil berwarna — status kirim / status tinjau.
class Lencana extends StatelessWidget {
  const Lencana({super.key, required this.teks, required this.latar, required this.depan, this.ikon});

  final String teks;
  final Color latar;
  final Color depan;
  final IconData? ikon;

  factory Lencana.statusKirim(BuildContext context, String status) {
    final w = context.warna;
    return switch (status) {
      'terkirim' => Lencana(teks: 'Terkirim', latar: w.okBg, depan: w.okFg, ikon: Icons.cloud_done_outlined),
      'ditolak' => Lencana(teks: 'Ditolak', latar: w.badBg, depan: w.badFg, ikon: Icons.block),
      'tertunda' => Lencana(teks: 'Menunggu data', latar: w.warnBg, depan: w.warnFg, ikon: Icons.hourglass_empty),
      'gagal' => Lencana(teks: 'Gagal, diulang', latar: w.warnBg, depan: w.warnFg, ikon: Icons.sync_problem),
      _ => Lencana(teks: 'Belum terkirim', latar: w.brandSoft, depan: w.brandStrong, ikon: Icons.cloud_upload_outlined),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[Icon(ikon, size: 14, color: depan), const SizedBox(width: 4)],
          Text(teks, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: depan)),
        ],
      ),
    );
  }
}
