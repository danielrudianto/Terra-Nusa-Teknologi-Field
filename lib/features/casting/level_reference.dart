import 'package:flutter/material.dart';

import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';

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
      'COL ${col == null ? 'belum ada' : formatElevation(col)}$nb·${nb}Tip ${tip == null ? 'belum ada' : formatElevation(tip)}',
    ];
    if (gs == null) {
      lines.add('Isi GS dulu untuk melihat kedalaman COL dan rencana bor.');
    } else {
      lines.add('GS ${formatElevation(gs)}');
      if (col != null) lines.add('• COL ${formatMeters(gs - col)} di bawah GS');
      if (tip != null) lines.add('• Rencana bor ${formatMeters(gs - tip)}');
    }
    return TerraBanner(
      kind: BannerKind.info,
      icon: Icons.height,
      title: 'Patokan elevasi',
      body: [
        ...lines,
        'Kedalaman bor diukur dari GS sampai dasar lubang.',
      ].join('\n'),
    );
  }
}
