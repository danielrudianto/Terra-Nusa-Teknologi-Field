import '../../core/i18n.dart';

/// THE NOTE ON A DRILL READING IS PICKED, NOT TYPED (Daniel, 24 Nov 2026:
/// "pas kasih catatan di app jadinya ada pilihannya gitu sih bang pengennya
/// biar seragam").
///
/// Typed notes said the same thing ten ways — "istirahat", "isoma", "rehat",
/// "mesin rusak", "trouble" — and nothing could be counted. Now the crew
/// picks one of three; only "Lainnya" still takes a few words.
///
/// What is STORED is the Indonesian text below, whatever language the phone
/// shows — the same rule as the site-mix supplier name "Lokal". The office
/// reads and counts one set of words; the phone only TRANSLATES them for
/// display ([drillNoteText]).
///
/// THREE choices only (Daniel, 24 Nov 2026): Istirahat, Kerusakan mesin, and
/// Lainnya — which is typed. A longer list was tried and cut back.
enum DrillReason {
  rest('Istirahat'),
  machine('Kerusakan mesin'),
  other('Lainnya');

  const DrillReason(this.stored);

  /// The text written to the database. NEVER translated.
  final String stored;

  String label(AppLocalizations l) => switch (this) {
        DrillReason.rest => l.reasonRest,
        DrillReason.machine => l.reasonMachine,
        DrillReason.other => l.reasonOther,
      };
}

/// `Lainnya: ...` — the one reason that carries free text.
const otherPrefix = 'Lainnya: ';

/// Read a stored note back: the reason, and the words for "Lainnya".
/// A note typed before this list existed comes back as "Lainnya" with its
/// own words, so editing an old reading never loses what was written.
({DrillReason? reason, String other}) parseDrillNote(String? note) {
  final n = note?.trim() ?? '';
  if (n.isEmpty) return (reason: null, other: '');
  for (final r in DrillReason.values) {
    if (r != DrillReason.other && n == r.stored) return (reason: r, other: '');
  }
  if (n == DrillReason.other.stored) return (reason: DrillReason.other, other: '');
  if (n.startsWith(otherPrefix)) return (reason: DrillReason.other, other: n.substring(otherPrefix.length));
  return (reason: DrillReason.other, other: n);
}

/// The note to store for [reason] and the "Lainnya" words, or null.
String? drillNoteOf(DrillReason? reason, String other) {
  if (reason == null) return null;
  if (reason != DrillReason.other) return reason.stored;
  final w = other.trim();
  return w.isEmpty ? DrillReason.other.stored : '$otherPrefix$w';
}

/// A stored note as the phone shows it, in the phone's language.
String drillNoteText(AppLocalizations l, String note) {
  final p = parseDrillNote(note);
  final r = p.reason;
  if (r == null) return note;
  if (r != DrillReason.other) return r.label(l);
  return p.other.isEmpty ? r.label(l) : '${r.label(l)}: ${p.other}';
}
