import 'package:flutter/material.dart';

/// One snackbar for the whole app: icon + one sentence, floating.
///
/// Shown after EVERY completed action, so "did it save?" never needs
/// guessing — the rule of the house. The previous snackbar is hidden first:
/// a burst of quick actions (adding tremie segments, say) must not queue up
/// a minute of stale toasts.
void showSnack(BuildContext context, String text, {IconData icon = Icons.check_circle_outline}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}
