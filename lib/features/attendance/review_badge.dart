import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/widgets/status_badge.dart';

/// Status on the server (result of the office review), pulled from `/sync/pull`.
class ReviewBadge extends StatelessWidget {
  const ReviewBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return switch (status) {
      'ditinjau' => StatusBadge(text: 'Disetujui kantor', bg: w.okBg, fg: w.okFg, icon: Icons.verified_outlined),
      'ditolak' => StatusBadge(text: 'Ditolak kantor', bg: w.badBg, fg: w.badFg, icon: Icons.report_outlined),
      'diperiksa' => StatusBadge(text: 'Diperiksa kantor', bg: w.okBg, fg: w.okFg, icon: Icons.verified_outlined),
      'selesai' => StatusBadge(text: 'Selesai', bg: w.infoBg, fg: w.infoFg, icon: Icons.flag_outlined),
      'berjalan' => StatusBadge(text: 'Berjalan', bg: w.warnBg, fg: w.warnFg, icon: Icons.timelapse),
      _ => StatusBadge(text: 'Menunggu tinjauan', bg: w.surface2, fg: w.muted, icon: Icons.hourglass_empty),
    };
  }
}
