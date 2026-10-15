import 'package:flutter/material.dart';

import '../i18n.dart';

/// Ask before doing something that changes a record people will later be
/// asked to vouch for.
///
/// The question names the CONSEQUENCE, not the operation: "the log opens
/// again and can be changed" rather than "are you sure?". Someone who is
/// sure of nothing in particular taps Yes to "are you sure?"; a sentence that
/// says what will happen is the only form of the question that can actually
/// be answered.
///
/// [danger] paints the confirming button in the error colour — for anything
/// that cannot be undone. Everything reversible keeps the ordinary button, so
/// that red never stops meaning "this one is different".
///
/// Returns `true` only on an explicit confirm: a dismissed dialog (back
/// button, tap outside) is a NO.
Future<bool> askConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  IconData icon = Icons.help_outline,
  bool danger = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(icon, size: 32),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(context).cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}
