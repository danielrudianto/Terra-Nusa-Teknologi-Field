import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// Short way to the translations: `t(context).navHome`.
///
/// The generated class is reached through one function so the rest of the
/// app never imports the generated file directly — if the generator's output
/// path or class name ever changes, it changes here and nowhere else.
///
/// That path HAS already changed once: `package:flutter_gen/...` was a
/// synthetic package Flutter dropped, and `flutter gen-l10n` now writes real
/// files next to the .arb files. This one import is why that cost two lines
/// instead of forty.
AppLocalizations t(BuildContext context) => AppLocalizations.of(context);

/// Translations for code that has NO widget tree: notification text, the
/// background sync worker, and pure helpers like reason codes.
///
/// [current] is filled in as soon as the app builds, and again whenever the
/// language changes. Before that — the background isolate on a cold start —
/// [load] fetches the right bundle for a locale directly.
class L10n {
  L10n._();

  static AppLocalizations? _current;

  /// The language the app is showing now. Null only before the first build.
  static AppLocalizations? get current => _current;

  static void remember(AppLocalizations value) => _current = value;

  /// For an isolate with no screen: the bundle for [code], falling back to
  /// Indonesian, which is the language of the site.
  static Future<AppLocalizations> load([String? code]) =>
      AppLocalizations.delegate.load(Locale(code ?? 'id'));
}
