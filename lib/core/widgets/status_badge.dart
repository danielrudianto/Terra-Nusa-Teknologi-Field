import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

/// Small colored badge — push status / review status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.text, required this.bg, required this.fg, this.icon});

  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  factory StatusBadge.sendStatus(BuildContext context, String status) {
    final w = context.colors;
    return switch (status) {
      'sent' => StatusBadge(text: 'Terkirim', bg: w.okBg, fg: w.okFg, icon: Icons.cloud_done_outlined),
      'rejected' => StatusBadge(text: 'Ditolak', bg: w.badBg, fg: w.badFg, icon: Icons.block),
      'deferred' => StatusBadge(text: 'Menunggu data', bg: w.warnBg, fg: w.warnFg, icon: Icons.hourglass_empty),
      'failed' => StatusBadge(text: 'Gagal, diulang', bg: w.warnBg, fg: w.warnFg, icon: Icons.sync_problem),
      _ => StatusBadge(text: 'Belum terkirim', bg: w.brandSoft, fg: w.brandStrong, icon: Icons.cloud_upload_outlined),
    };
  }

  @override
  Widget build(BuildContext context) {
    // "Belum terkirim" -> "Terkirim" is the moment the foreman waits for, so
    // the badge melts between the two instead of swapping in place.
    return AnimatedContainer(
      duration: Dimens.motionMedium,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: AnimatedSwitcher(
        duration: Dimens.motionFast,
        child: Row(
          key: ValueKey('$text$icon'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
