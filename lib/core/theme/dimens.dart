import 'package:flutter/widgets.dart';

/// Sizes used repeatedly — from `app/mobile/_mobile.scss`.
class Dimens {
  Dimens._();

  /// `$sentuh-minimum`: below this, someone walking while holding the
  /// phone misses and hits the neighboring button.
  static const double minTouch = 48;

  /// List card: radius 16, banner: radius 12.
  static const double radiusCard = 16;
  static const double radiusBanner = 12;

  /// `--gerak-cepat` 140 ms, `--gerak-sedang` 220 ms.
  static const Duration motionFast = Duration(milliseconds: 140);
  static const Duration motionMedium = Duration(milliseconds: 220);

  /// Page edge spacing.
  static const double pagePadding = 16;
}

/// Bottom padding for a modal bottom sheet, so its last button is never left
/// under the keyboard or under the system navigation bar.
///
/// `viewInsets.bottom` is the KEYBOARD. `padding.bottom` is what the system
/// bars still cover AFTER the keyboard is taken into account — it drops to
/// zero while the keyboard hides the navigation bar — so adding the two never
/// double-counts. Using only `viewInsets` (what every sheet here did before)
/// leaves the save button sitting behind the three-button navigation bar on
/// phones that have one.
EdgeInsets sheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
      Dimens.pagePadding,
      0,
      Dimens.pagePadding,
      MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + Dimens.pagePadding,
    );
