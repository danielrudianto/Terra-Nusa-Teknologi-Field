import 'package:flutter/material.dart';

import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/i18n.dart';

/// Signed elevation, e.g. "+12,50" / "-3,25".
String formatElevation(double v, {int decimals = 2}) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(decimals).replaceAll('.', ',')}';

/// The reference levels of a pile point, shown where the foreman types GS and
/// drill depth, so he knows what the numbers are measured against.
///
/// With a GS ([groundLevel], e.g. the one being typed) it also turns the
/// elevations into depths from the ground: how far below GS the cut-off (COL)
/// sits and how deep the hole is planned to go.
class LevelReferenceBanner extends StatelessWidget {
  const LevelReferenceBanner({
    super.key,
    required this.cutOffLevel,
    required this.tipLevel,
    this.groundLevel,
  });

  final double? cutOffLevel;
  final double? tipLevel;
  final double? groundLevel;

  @override
  Widget build(BuildContext context) {
    final col = cutOffLevel;
    final tip = tipLevel;
    final gs = groundLevel;
    const nb = '\u00A0';
    final lines = <String>[
      t(context)
          .levelRefColTip(col == null ? t(context).notSet : formatElevation(col),
              tip == null ? t(context).notSet : formatElevation(tip))
          .replaceAll(' · ', '$nb·$nb'),
    ];
    if (gs == null) {
      lines.add(t(context).levelRefNoGs);
    } else {
      lines.add(t(context).levelRefGs(formatElevation(gs)));
      if (col != null) lines.add(t(context).levelRefColBelow(formatMeters(gs - col)));
      if (tip != null) lines.add(t(context).levelRefPlanned(formatMeters(gs - tip)));
    }
    return TerraBanner(
      kind: BannerKind.info,
      icon: Icons.height,
      title: t(context).levelRefTitle,
      body: [
        ...lines,
        t(context).levelRefFooter,
      ].join('\n'),
    );
  }
}
