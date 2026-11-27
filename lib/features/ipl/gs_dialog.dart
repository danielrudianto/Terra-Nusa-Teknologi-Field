import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../casting/gs_guard.dart';
import '../casting/level_reference.dart';

/// Enter the measured GS of ONE point, with its design GS beside it
/// (Daniel, 24 Nov 2026: "pas centang muncul in dialog untuk isi GS, kasih
/// tau juga GS design ya berapa. Jadi minim salah").
///
/// The difference to the design GS is shown while typing. Past 30 cm a
/// warning banner sits at the TOP and Simpan asks once more; past 10 m it is
/// refused with a guess of the meant number (6819 → 681,9 — SP.D3, 27 Nov
/// 2026). See `gs_guard.dart`. Below the tip is refused — the server refuses
/// it too.
///
/// Returns the GS, or `null` when cancelled. The text controller lives in the
/// dialog's own State (see `number_dialog.dart` for why).
Future<double?> showGsDialog(
  BuildContext context, {
  required Map<String, Object?> pile,
  required double? initial,
  required String confirmLabel,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _GsDialog(pile: pile, initial: initial, confirmLabel: confirmLabel),
  );
}

class _GsDialog extends StatefulWidget {
  const _GsDialog({required this.pile, required this.initial, required this.confirmLabel});

  final Map<String, Object?> pile;
  final double? initial;
  final String confirmLabel;

  @override
  State<_GsDialog> createState() => _GsDialogState();
}

class _GsDialogState extends State<_GsDialog> {
  late final _input = TextEditingController(
    text: widget.initial == null ? '' : decimalText(widget.initial!, decimals: 3).replaceAll('.', ','),
  );
  String? _problem;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  double? get _design => toDoubleOrNull(widget.pile['groundLevel']);
  double? get _tip => toDoubleOrNull(widget.pile['tipLevel']);

  double? get _col => toDoubleOrNull(widget.pile['cutOffLevel']);

  Future<void> _submit() async {
    final l = t(context);
    final v = parseNumber(_input.text);
    if (v == null) {
      setState(() => _problem = l.iplGsInvalid);
      return;
    }
    final tip = _tip;
    if (tip != null && v <= tip) {
      setState(() => _problem = l.iplGsBelowTip(formatElevation(tip)));
      return;
    }
    if (!await gsConfirmIfFar(context, typed: v, design: _design, cutOffLevel: _col)) return;
    if (!mounted) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final design = _design;
    final tip = _tip;
    final col = _col;
    final dia = toIntOrNull(widget.pile['diameterMm']);
    final typed = parseNumber(_input.text);
    final diff = typed != null && design != null ? typed - design : null;
    final refused = gsRefused(typed, design: design, cutOffLevel: col);

    Widget fact(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: w.muted))),
              Text(
                value,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  fontSize: strong ? 17 : 14,
                  color: w.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      icon: Icon(Icons.straighten, size: 32, color: w.brand),
      title: Text('${widget.pile['code']}', textAlign: TextAlign.center),
      // Scrolled: with the keyboard open, a short phone has no room left
      // and the field itself is what would be pushed out.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GsGuardBanner(
              typed: typed,
              design: design,
              cutOffLevel: col,
              onUse: (v) => setState(() {
                _input.text = gsInputText(v);
                _problem = null;
              }),
            ),
            fact(l.iplGsDesign, design == null ? '—' : formatElevation(design, decimals: 3), strong: true),
            if (col != null) fact('COL', formatElevation(col)),
            if (tip != null) fact('Tip', formatElevation(tip)),
            if (dia != null && dia > 0) fact('Ø', '$dia mm'),
            const SizedBox(height: 20),
            TextField(
              controller: _input,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
              decoration: InputDecoration(labelText: l.iplGsLabel, suffixText: 'm'),
              onChanged: (_) => setState(() => _problem = null),
              onSubmitted: (_) => _submit(),
            ),
            // Selisihnya saja, selalu tenang: peringatannya sudah di banner atas.
            if (diff != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.compare_arrows, size: 18, color: w.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.iplGsDiff(gsSigned(diff)), style: TextStyle(color: w.muted))),
                ],
              ),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: w.badFg),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_problem!, style: TextStyle(color: w.badFg))),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          // Mati selama GS-nya mustahil — alasannya banner merah di atas.
          onPressed: _input.text.trim().isEmpty || refused ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
