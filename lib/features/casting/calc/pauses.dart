/// Stopwatch pauses while one TM is being poured.
///
/// A pause is a map in the casting document's `pauses` list, exactly the
/// server's `JedaCor`: uuid, truckSeq, startAt, endAt (null = still paused),
/// reason, note. Times are ISO strings with offset.
library;

/// Reason codes as the server spells them, with what the screen shows.
const pauseReasons = <String, String>{
  'cabut_tremie': 'Cabut tremie',
  'tunggu_tm': 'Tunggu TM',
  'kendala_alat': 'Kendala alat',
  'lainnya': 'Lainnya',
};

/// A TM still pouring after this long (pauses not counted) makes the phone
/// buzz once, and its timer turns red.
const truckReminderAfter = Duration(minutes: 20);

String pauseReasonLabel(Object? code) => pauseReasons['$code'] ?? 'Lainnya';

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Pauses of TM [seq], oldest first.
List<Map<String, Object?>> pausesOf(List<Map<String, Object?>> pauses, int seq) {
  final list = [for (final p in pauses) if ('${p['truckSeq']}' == '$seq') p];
  list.sort((a, b) => '${a['startAt']}'.compareTo('${b['startAt']}'));
  return list;
}

/// The pause of TM [seq] that has not ended, if any.
Map<String, Object?>? openPause(List<Map<String, Object?>> pauses, int seq) {
  for (final p in pausesOf(pauses, seq)) {
    if (p['endAt'] == null) return p;
  }
  return null;
}

/// Total paused time of TM [seq]; an open pause counts up to [now].
Duration pausedTime(List<Map<String, Object?>> pauses, int seq, DateTime now) {
  var total = Duration.zero;
  for (final p in pausesOf(pauses, seq)) {
    final start = _time(p['startAt']);
    if (start == null) continue;
    final end = _time(p['endAt']) ?? now;
    if (end.isAfter(start)) total += end.difference(start);
  }
  return total;
}

/// Pouring time of a truck: from start to end (or [now] while pouring),
/// minus its pauses. Null before it starts.
Duration? pouringTime(Map<String, Object?> truck, List<Map<String, Object?>> pauses, DateTime now) {
  final start = _time(truck['startAt']);
  if (start == null) return null;
  final end = _time(truck['endAt']) ?? now;
  final seq = int.tryParse('${truck['seq']}') ?? 0;
  final net = end.difference(start) - pausedTime(pauses, seq, end);
  return net.isNegative ? Duration.zero : net;
}
