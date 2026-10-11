/// Parts of the app that can be switched off for a release without deleting
/// their code. Flip a flag back to `true` to bring the part back as it was.
abstract final class Features {
  /// Crew attendance and the worker list (registering workers only serves
  /// attendance). On hold since 9 Oct 2026 (Daniel): the first release is
  /// drilling & casting only. While off, the Absensi tab, the home shortcuts
  /// and every /attendance and /workers route are hidden; documents already
  /// on a phone still sync.
  static const attendance = false;
}
