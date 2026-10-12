/// Commands to the TM being poured that come from OUTSIDE the casting screen.
///
/// The screen is not the only way to stop a pour. The "Selesai TM" button on
/// the stopwatch notification works with the phone in a pocket, and a
/// smartwatch button does the same. Both arrive here, in ONE pure function, so
/// the rules live in one place and are testable without a screen, a database
/// or a clock.
///
/// The caller stores the body; this file never touches a database.
library;

import '../../../core/util/format.dart';
import 'pauses.dart';
import '../../../core/i18n.dart';

/// A TM that lives on the server is never deleted — it can only be stopped.
enum TruckCommand {
  /// Stop the pouring clock without ending the TM (tremie out, waiting).
  pause,

  /// Start the clock again after a [pause].
  resume,

  /// End the TM: the pour is finished.
  finish,
}

/// What a command did, or why it did nothing.
class TruckCommandResult {
  const TruckCommandResult.applied({required this.seq, required this.needsSounding}) : refusal = null;

  /// The command did not apply; [refusal] says why, in Indonesian, for a banner.
  const TruckCommandResult.refused(String this.refusal) : seq = null, needsSounding = false;

  /// Sentence shown to the user when nothing changed. Null when it applied.
  final String? refusal;

  /// The TM the command acted on. Null when it was refused.
  final int? seq;

  /// [TruckCommand.finish] only: the sounding after this TM is still missing.
  ///
  /// The screen MUST ask for it ([CastingForm] does, and every number after it
  /// stands on it). A watch button cannot answer a dialog, so finishing from
  /// outside the screen deliberately leaves the sounding for the phone.
  final bool needsSounding;

  bool get applied => refusal == null;
}

/// The TM still being poured: started, not finished. The highest seq wins.
Map<String, Object?>? runningTruckOf(Map<String, Object?> body) {
  Map<String, Object?>? found;
  for (final x in (body['trucks'] as List? ?? const [])) {
    if (x is! Map) continue;
    final t = x.cast<String, Object?>();
    if (t['startAt'] == null || t['endAt'] != null) continue;
    if (found == null || (toIntOrNull(t['seq']) ?? 0) > (toIntOrNull(found['seq']) ?? 0)) found = t;
  }
  return found;
}

/// The `pauses` list of [body], GROWABLE and written back into the body.
///
/// Always a fresh growable list holding the SAME pause maps: a body decoded
/// from JSON or built in a test may carry an unmodifiable list, and `.add`
/// on that throws. Because the list is written back into [body], what this
/// function returns is exactly what gets stored — and because only the LIST
/// is copied, never the maps, closing a pause still lands in the body.
List<Object?> _pausesListOf(Map<String, Object?> body) {
  final existing = body['pauses'];
  final list = existing is List ? List<Object?>.of(existing) : <Object?>[];
  body['pauses'] = list;
  return list;
}

/// Apply one command that came from outside the screen to a casting body.
///
/// [at] is the moment of the command, [pauseUuid] is the uuid of the pause it
/// may add, [pauseReason] is a code from [pauseReasons]. All three are passed
/// in so this function stays pure.
///
/// The body is changed in place; the caller is responsible for storing it.
TruckCommandResult applyTruckCommand(
  Map<String, Object?> body,
  TruckCommand command, {
  required DateTime at,
  required String pauseUuid,
  String pauseReason = 'lainnya',
}) {
  if (body['status'] == 'selesai') {
    return TruckCommandResult.refused(L10n.current?.castAlreadyDone ?? 'Cor titik ini sudah selesai.');
  }
  final truck = runningTruckOf(body);
  if (truck == null) {
    return TruckCommandResult.refused(L10n.current?.noTruckPouring ?? 'Tidak ada TM yang sedang dicor.');
  }
  final seq = toIntOrNull(truck['seq']) ?? 0;
  final raw = _pausesListOf(body);
  // A VIEW of the stored maps, so closing a pause here closes it in the body.
  final pauses = [for (final p in raw) if (p is Map) p.cast<String, Object?>()];
  final open = openPause(pauses, seq);

  switch (command) {
    case TruckCommand.pause:
      if (open != null) return TruckCommandResult.refused(L10n.current?.truckAlreadyPaused(seq) ?? 'TM #$seq sudah dijeda.');
      raw.add(<String, Object?>{
        'uuid': pauseUuid,
        'truckSeq': seq,
        'startAt': isoWithOffset(at),
        'endAt': null,
        'reason': pauseReason,
        'note': null,
      });
      return TruckCommandResult.applied(seq: seq, needsSounding: false);

    case TruckCommand.resume:
      if (open == null) return TruckCommandResult.refused(L10n.current?.truckNotPaused(seq) ?? 'TM #$seq tidak sedang dijeda.');
      open['endAt'] = isoWithOffset(at);
      return TruckCommandResult.applied(seq: seq, needsSounding: false);

    case TruckCommand.finish:
      // A TM stopped while it was paused stays stopped: close the pause too, or
      // its paused time would keep growing for ever.
      if (open != null) open['endAt'] = isoWithOffset(at);
      truck['endAt'] = isoWithOffset(at);
      return TruckCommandResult.applied(seq: seq, needsSounding: truck['concreteDepthAfterM'] == null);
  }
}
