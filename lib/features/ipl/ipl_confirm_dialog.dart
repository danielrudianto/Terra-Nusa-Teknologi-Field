import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../casting/level_reference.dart';

/// One point as the surveyor will send it.
typedef IplConfirmLine = ({String code, String? kind, double gs, double? design});

/// READ IT BACK BEFORE SENDING (Daniel, 24 Nov 2026: "sebelum submit ...
/// dialog confirm isinya itu titik titik yang tadi dia pilih untuk di baca
/// ulang").
///
/// Every ticked point on its own line — code, what it is cleared for, the
/// GS it goes with and its difference to the design GS — so a wrong tick or
/// a mistyped GS is caught here, not by the office or the rig. The list
/// scrolls inside the dialog; the buttons stay in view.
///
/// Returns `true` to send.
Future<bool> showIplConfirmDialog(
  BuildContext context, {
  required String dateText,
  required List<IplConfirmLine> lines,
}) async {
  final w = context.colors;
  final l = t(context);
  String signed(double v) {
    final s = formatElevation(v.abs(), decimals: 3).replaceFirst('+', '');
    return '${v > 0.0005 ? '+' : v < -0.0005 ? '−' : '±'}$s';
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.fact_check_outlined, size: 32, color: w.brand),
      title: Text(l.iplConfirmTitle, textAlign: TextAlign.center),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.iplConfirmLead(dateText, '${lines.length}'),
              style: TextStyle(color: w.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: w.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: w.line),
                  itemBuilder: (_, i) {
                    final x = lines[i];
                    final diff = x.design == null ? null : x.gs - x.design!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('${i + 1}', style: TextStyle(color: w.muted, fontSize: 13)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(x.code, style: TextStyle(fontWeight: FontWeight.w800, color: w.ink)),
                                if (x.kind != null)
                                  Text(
                                    x.kind!,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: w.warnFg),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatElevation(x.gs, decimals: 3),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: w.ink,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              if (diff != null)
                                Text(
                                  l.iplConfirmDiff(signed(diff)),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: diff.abs() > 0.30 ? w.warnFg : w.muted,
                                    fontWeight: diff.abs() > 0.30 ? FontWeight.w700 : null,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(l.iplConfirmFoot, style: TextStyle(color: w.muted, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.iplConfirmBack)),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.send, size: 18),
          label: Text(l.send),
        ),
      ],
    ),
  );
  return ok ?? false;
}
