/// A worker who can be marked for attendance.
///
/// Workers belong to the company, not to whoever registered them: every user
/// of the field app sees every worker and may absent or correct any of them.
/// The project fields only group and sort; they never restrict where a worker
/// can be absent, because crews move between sites.
class Worker {
  const Worker({
    required this.uuid,
    required this.name,
    this.phone,
    this.active = true,
    this.isLocal = false,
    this.photoUuid,
    this.projectId,
    this.lastProjectId,
    this.lastSeenDate,
  });

  final String uuid;
  final String name;
  final String? phone;
  final bool active;

  /// Not on the server yet.
  final bool isLocal;
  final String? photoUuid;

  /// Main project, chosen by whoever registered or last edited the worker.
  final int? projectId;

  /// Where and when the worker was last absent, kept by the server.
  final int? lastProjectId;
  final DateTime? lastSeenDate;

  /// How long a worker still counts as "on" the site where they were last absent.
  static const recentDays = 14;

  /// Main project is [project], or the worker was absent there in the last
  /// [recentDays] days.
  bool belongsTo(int project, DateTime today) {
    if (projectId == project) return true;
    if (lastProjectId != project || lastSeenDate == null) return false;
    final day = DateTime(today.year, today.month, today.day);
    return day.difference(lastSeenDate!).inDays <= recentDays;
  }

  /// Every project this worker currently counts toward (see [belongsTo]).
  Set<int> projectsOn(DateTime today) => {
        ?projectId,
        if (lastProjectId != null && belongsTo(lastProjectId!, today)) lastProjectId!,
      };
}

/// Lower case, single spaces, no punctuation: "  Asep  S." -> "asep s".
String normalizeName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Digits only, with a leading 62 read as 0: "+62 812-3" -> "08123".
String normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
}

/// Workers who may be the same person as the one being registered.
///
/// Same phone number, or one name equal to or the start of the other
/// ("Asep" vs "Asep Saepudin"). Since everyone can now register workers,
/// the same person is easily registered twice by two people; the form asks
/// before saving instead of refusing, because two people may share a name.
List<Worker> possibleDuplicates(Iterable<Worker> workers, {required String uuid, required String name, String? phone}) {
  final n = normalizeName(name);
  final p = phone == null ? '' : normalizePhone(phone);
  if (n.isEmpty && p.length < 6) return const [];
  bool sameName(String other) {
    final o = normalizeName(other);
    if (n.isEmpty || o.isEmpty) return false;
    return o == n || o.startsWith('$n ') || n.startsWith('$o ');
  }

  return [
    for (final w in workers)
      if (w.uuid != uuid &&
          (sameName(w.name) || (p.length >= 6 && w.phone != null && normalizePhone(w.phone!) == p)))
        w,
  ];
}
