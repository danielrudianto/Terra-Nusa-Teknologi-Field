import 'package:flutter/material.dart';

import '../../core/i18n.dart';
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
      'ditinjau' => StatusBadge(text: t(context).reviewApproved, bg: w.okBg, fg: w.okFg, icon: Icons.verified_outlined),
      'ditolak' => StatusBadge(text: t(context).rejectedByOffice, bg: w.badBg, fg: w.badFg, icon: Icons.report_outlined),
      'diperiksa' => StatusBadge(text: t(context).reviewChecked, bg: w.okBg, fg: w.okFg, icon: Icons.verified_outlined),
      'selesai' => StatusBadge(text: t(context).done, bg: w.infoBg, fg: w.infoFg, icon: Icons.flag_outlined),
      'berjalan' => StatusBadge(text: t(context).reviewRunning, bg: w.warnBg, fg: w.warnFg, icon: Icons.timelapse),
      _ => StatusBadge(text: t(context).reviewWaiting, bg: w.surface2, fg: w.muted, icon: Icons.hourglass_empty),
    };
  }
}
