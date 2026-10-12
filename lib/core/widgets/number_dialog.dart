import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../util/decimal_input.dart';
import '../util/format.dart';
import '../i18n.dart';

/// Ask for one number in a dialog.
///
/// Returns null when cancelled, `(null,)` when left empty (only with
/// [allowEmpty]), or `(value,)`.
///
/// The text controller lives in the dialog's own State, never in the caller.
/// A caller that disposes its controller right after `showDialog` returns
/// kills it while the dialog is still animating out with the TextField
/// mounted, and Flutter stops with "'_dependents.isEmpty': is not true".
Future<(double?,)?> showNumberDialog(
  BuildContext context, {
  required String title,
  required String label,
  required IconData icon,
  String? suffix,
  required double maxValue,
  double? initial,
  String? hint,
  bool allowEmpty = false,
  String? Function(double value)? validate,
}) {
  return showDialog<(double?,)>(
    context: context,
    builder: (_) => _NumberDialog(
      title: title,
      label: label,
      icon: icon,
      suffix: suffix,
      maxValue: maxValue,
      initial: initial,
      hint: hint,
      allowEmpty: allowEmpty,
      validate: validate,
    ),
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.label,
    required this.icon,
    required this.suffix,
    required this.maxValue,
    required this.initial,
    required this.hint,
    required this.allowEmpty,
    required this.validate,
  });

  final String title;
  final String label;
  final IconData icon;
  final String? suffix;
  final double maxValue;
  final double? initial;
  final String? hint;
  final bool allowEmpty;

  /// Extra check on a number in range; returns the sentence to show, or null.
  final String? Function(double value)? validate;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _input = TextEditingController(
    text: widget.initial == null ? '' : widget.initial!.toStringAsFixed(2).replaceAll('.', ','),
  );
  String? _problem;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _input.text.trim();
    if (typed.isEmpty && widget.allowEmpty) {
      Navigator.pop(context, (null,));
      return;
    }
    final v = parseNumber(typed);
    if (v == null || v <= 0 || v > widget.maxValue) {
      setState(() => _problem = t(context).numberInvalid(decimalText(widget.maxValue, decimals: 0)));
      return;
    }
    final wrong = widget.validate?.call(v);
    if (wrong != null) {
      setState(() => _problem = wrong);
      return;
    }
    Navigator.pop(context, (v,));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return AlertDialog(
      icon: Icon(widget.icon, size: 32, color: w.brand),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.hint != null) Text(widget.hint!, style: TextStyle(color: w.muted, height: 1.4)),
          // Room for the floating label, which sits ON the field's top border.
          const SizedBox(height: 20),
          TextField(
            controller: _input,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // No more integer digits than the largest allowed value has.
            inputFormatters: decimalInput(maxIntDigits: widget.maxValue.floor().toString().length),
            decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
            onSubmitted: (_) => _submit(),
          ),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context).cancel)),
        FilledButton(onPressed: _submit, child: Text(t(context).save)),
      ],
    );
  }
}
