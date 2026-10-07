/// Ukuran yang dipakai berulang — dari `app/mobile/_mobile.scss`.
class Ukuran {
  Ukuran._();

  /// `$sentuh-minimum`: di bawah ini, orang yang berjalan sambil memegang
  /// HP meleset ke tombol sebelahnya.
  static const double sentuhMinimum = 48;

  /// Kartu daftar: radius 16, banner: radius 12.
  static const double radiusKartu = 16;
  static const double radiusBanner = 12;

  /// `--gerak-cepat` 140 ms, `--gerak-sedang` 220 ms.
  static const Duration gerakCepat = Duration(milliseconds: 140);
  static const Duration gerakSedang = Duration(milliseconds: 220);

  /// Jarak tepi halaman.
  static const double tepi = 16;
}
