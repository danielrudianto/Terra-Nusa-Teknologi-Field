import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

enum BannerKind { info, warning, danger, ok }

/// TerraBot banner: icon on the left, bold title, then an explanatory sentence.
///
/// Mirrors `.pou-banner` / `.plc-banner` on the web. THIS replaces the small hint
/// under a field — every explanation that needs to be read goes in here, in
/// type that is readable on a phone held at arm's length.
class TerraBanner extends StatelessWidget {
  const TerraBanner({
    super.key,
    required this.kind,
    required this.title,
    this.body,
    this.icon,
    this.action,
  });

  final BannerKind kind;
  final String title;
  final String? body;
  final IconData? icon;

  /// Optional button on the right (e.g. "Coba lagi", "Masuk").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final (bg, fg, defaultIcon) = switch (kind) {
      BannerKind.info => (w.brandSoft, w.brandStrong, Icons.info_outline),
      BannerKind.warning => (w.warnBg, w.warnFg, Icons.warning_amber_rounded),
      BannerKind.danger => (w.badBg, w.badFg, Icons.error_outline),
      BannerKind.ok => (w.okBg, w.okFg, Icons.check_circle_outline),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Dimens.radiusBanner),
        // A hairline under 1 px can vanish on some rows of the screen and makes
        // the banner look cut off; 1 px with a softer colour stays whole.
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? defaultIcon, size: 22, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              // Content height only. Without this the banner fills all the
              // height it is offered — in a Scaffold's bottomNavigationBar
              // that is the whole screen ("Cor selesai" turned the page green).
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg),
                ),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: TextStyle(fontSize: 14, height: 1.4, color: fg)),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
