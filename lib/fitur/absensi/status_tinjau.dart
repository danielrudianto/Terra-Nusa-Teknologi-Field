import 'package:flutter/material.dart';

import '../../inti/tema/token_warna.dart';
import '../../inti/widget/lencana.dart';

/// Status di server (hasil tinjauan kantor), ditarik dari `/sync/pull`.
class LencanaTinjau extends StatelessWidget {
  const LencanaTinjau({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return switch (status) {
      'ditinjau' => Lencana(teks: 'Disetujui kantor', latar: w.okBg, depan: w.okFg, ikon: Icons.verified_outlined),
      'ditolak' => Lencana(teks: 'Ditolak kantor', latar: w.badBg, depan: w.badFg, ikon: Icons.report_outlined),
      'diperiksa' => Lencana(teks: 'Diperiksa kantor', latar: w.okBg, depan: w.okFg, ikon: Icons.verified_outlined),
      'selesai' => Lencana(teks: 'Selesai', latar: w.infoBg, depan: w.infoFg, ikon: Icons.flag_outlined),
      'berjalan' => Lencana(teks: 'Berjalan', latar: w.warnBg, depan: w.warnFg, ikon: Icons.timelapse),
      _ => Lencana(teks: 'Menunggu tinjauan', latar: w.surface2, depan: w.muted, ikon: Icons.hourglass_empty),
    };
  }
}
