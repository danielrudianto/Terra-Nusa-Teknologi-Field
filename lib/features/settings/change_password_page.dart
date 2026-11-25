import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/dimens.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/terra_banner.dart';

/// CHANGE PASSWORD from the phone (Daniel, 25 Nov 2026).
///
/// The same endpoint the web uses (`PUT /users/me/password`): the current
/// password is required, the new one must differ and be at least
/// [minLength] characters — the server's own rule, checked here first so a
/// typo is caught before the round trip. Needs the internet; the phone
/// keeps no password of its own, only tokens, so nothing on the phone has
/// to change afterwards and the user stays signed in.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  /// `PasswordChange.newPassword` on the server: `min_length=6`.
  static const minLength = 6;

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _show = false;
  bool _busy = false;

  /// The one problem worth showing, in a banner above the button.
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  /// The server answers these three with the bare code as its message.
  String _messageOf(ApiError e, AppLocalizations l) {
    final key = e.code ?? e.message;
    return switch (key) {
      'CURRENT_PASSWORD_INVALID' => l.pwCurrentWrong,
      'PASSWORD_UNCHANGED' => l.pwSameAsOld,
      'PASSWORD_UNSET' => l.pwUnset,
      _ => e.message,
    };
  }

  Future<void> _save() async {
    final l = t(context);
    final current = _current.text;
    final next = _next.text;
    final String? problem;
    if (current.isEmpty) {
      problem = l.pwCurrentEmpty;
    } else if (next.length < ChangePasswordPage.minLength) {
      problem = l.pwTooShort(ChangePasswordPage.minLength);
    } else if (next != _repeat.text) {
      problem = l.pwMismatch;
    } else if (next == current) {
      problem = l.pwSameAsOld;
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).changePassword(current: current, next: next);
      if (!mounted) return;
      showSnack(context, l.pwChanged);
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = _messageOf(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    Widget field(TextEditingController c, String label, List<String> hints, {TextInputAction? action}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: c,
            obscureText: !_show,
            enabled: !_busy,
            autofillHints: hints,
            textInputAction: action ?? TextInputAction.next,
            onSubmitted: action == TextInputAction.done ? (_) => _save() : null,
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: IconButton(
                tooltip: _show ? l.pwHide : l.pwShow,
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l.pwTitle)),
      body: AutofillGroup(
        child: ListView(
          padding: pagePaddingAman(context),
          children: [
            TerraBanner(kind: BannerKind.info, title: l.pwInfoTitle, body: l.pwInfoBody(ChangePasswordPage.minLength)),
            const SizedBox(height: 16),
            field(_current, l.pwCurrent, const [AutofillHints.password]),
            field(_next, l.pwNew, const [AutofillHints.newPassword]),
            field(_repeat, l.pwRepeat, const [AutofillHints.newPassword], action: TextInputAction.done),
            if (_error != null) ...[
              TerraBanner(kind: BannerKind.danger, title: _error!),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.lock_reset),
              label: Text(l.pwSave),
            ),
          ],
        ),
      ),
    );
  }
}
