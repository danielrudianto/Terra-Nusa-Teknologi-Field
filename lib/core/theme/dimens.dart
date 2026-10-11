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
