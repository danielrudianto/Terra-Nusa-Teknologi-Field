/// PEMERIKSAAN GS YANG DIKETIK (27 Nov 2026).
///
/// SP.D3 dan SP.D7 masuk IPL dengan GS 6.819,000 dan 6.812,076 — maksudnya
/// 681,9 dan 681,2: komanya tertinggal. Peringatannya hanya satu baris kecil
/// di bawah isian, dan di HP yang hurufnya diperbesar baris itu terdorong
/// keluar layar. Daniel: "max perbedaan GS 10 meter juga kayanya udah aneh".
///
/// Aturannya:
///   * Selisih dengan ACUAN (GS desain, atau COL bila desain kosong) lebih
///     dari [gsMaxGapM] = DITOLAK, dengan tebakan angka yang dimaksud.
///   * Selisih lebih dari [gsWarnGapM] = boleh, tetapi ditanya dulu.
library;

/// Lebih jauh dari ini dari acuan: hampir pasti salah ketik. Ditolak.
const double gsMaxGapM = 10.0;

/// Lebih jauh dari ini: mungkin benar (tanah memang berubah), ditanya dulu.
const double gsWarnGapM = 0.30;

/// Acuan pembanding: GS desain bila ada, selain itu COL.
///
/// GS "desain" di HP bisa sendiri sudah hasil salah ketik yang tersimpan
/// (6.819 dari SP.D3). Bila ia lebih dari [gsMaxGapM] dari COL — yang selalu
/// dari gambar — COL yang dipakai, supaya angka yang BENAR tidak ditolak
/// karena dibandingkan dengan angka yang salah.
double? gsReference({double? design, double? cutOffLevel}) {
  if (design != null && cutOffLevel != null && (design - cutOffLevel).abs() > gsMaxGapM) {
    return cutOffLevel;
  }
  return design ?? cutOffLevel;
}

/// `true` bila [typed] terlalu jauh dari [reference] untuk dapat benar.
bool gsImpossible(double typed, double? reference) =>
    reference != null && (typed - reference).abs() > gsMaxGapM + 1e-9;

/// `true` bila [typed] cukup jauh untuk ditanyakan dulu (tetapi masih mungkin).
bool gsNeedsConfirm(double typed, double? reference) =>
    reference != null &&
    !gsImpossible(typed, reference) &&
    (typed - reference).abs() > gsWarnGapM + 1e-9;

/// Tebakan angka yang dimaksud: [typed] dengan koma yang bergeser (÷10,
/// ÷100, ÷1000, ×10, ×100) yang jatuh paling dekat ke [reference] — dan
/// hanya bila hasilnya masuk akal (dalam [gsMaxGapM]). `null` bila tidak ada.
double? gsSuggestion(double typed, double? reference) {
  if (reference == null) return null;
  double? best;
  for (final f in const [0.1, 0.01, 0.001, 10.0, 100.0]) {
    final c = typed * f;
    if ((c - reference).abs() > gsMaxGapM) continue;
    if (best == null || (c - reference).abs() < (best - reference).abs()) best = c;
  }
  return best == null ? null : (best * 1000).round() / 1000;
}
