import 'dart:math' as math;

import '../../../core/util/format.dart';
import 'volume.dart';
import '../../../core/i18n.dart';

/// Casting state RIGHT NOW, read from the casting log document on the phone.
///
/// No number is stored twice: the installed tremie length, its bottom
/// end, and the concrete level are all derived from the segments ticked as
/// removed and each truck's sounding. Changing one tick changes everything
/// by itself.
class CastingState {
  CastingState._({
    required this.geometry,
    required this.bottomGapM,
    required this.tremieStartMeasured,
    required this.segments,
    required this.trucks,
  });

  factory CastingState.from(PileGeometry geometry, Map<String, Object?> doc) {
    // Ujung bawah tremie saat mulai cor: DIUKUR bila ada, diturunkan dari
    // celah bila tidak.
    //
    // Celahnya dulu diisi tangan sebagai asumsi dan seluruh angka tertanam
    // berdiri di atasnya. Sejak 14 Okt 2026 QS mengukur kedalaman ujung
    // tremie langsung, dan celahnya menjadi turunan. Log lama tidak punya
    // kolomnya — angkanya tidak boleh bergeser hanya karena kolomnya
    // bertambah, jadi jalur lamanya dipertahankan.
    final diukur = toDoubleOrNull(doc['tremieDepthStartM']);
    return CastingState._(
      geometry: geometry,
      tremieStartMeasured: diukur != null,
      // 1 m di atas dasar lubang (Daniel, 12 Okt 2026 — sebelumnya 0,30 m).
      // Log cor yang sudah ada menyimpan angkanya sendiri, jadi yang lama
      // tetap 0,30; hanya log baru yang mulai dari 1 m.
      bottomGapM: diukur != null
          ? geometry.bottomDepthM - diukur
          : toDoubleOrNull(doc['tremieBottomGapM']) ?? 1.00,
      segments: [
        for (final s in (doc['tremie'] as List?) ?? const [])
          TremieSegment.fromJson((s as Map).cast<String, Object?>()),
      ]..sort((a, b) => a.position.compareTo(b.position)),
      trucks: [
        for (final t in (doc['trucks'] as List?) ?? const []) TruckRecord.fromJson((t as Map).cast<String, Object?>()),
      ]..sort((a, b) => a.seq.compareTo(b.seq)),
    );
  }

  final PileGeometry geometry;

  /// Celah ujung tremie di atas dasar lubang. DITURUNKAN dari kedalaman
  /// tremie terukur bila ada; angka yang diisi tangan bila tidak.
  final double bottomGapM;

  /// Celahnya datang dari kedalaman tremie yang DIUKUR, bukan dari asumsi.
  final bool tremieStartMeasured;

  /// Ordered by position, 1 = BOTTOM-MOST.
  final List<TremieSegment> segments;
  final List<TruckRecord> trucks;

  /// Segments still installed AFTER truck number [seq] (0 = before truck 1).
  List<TremieSegment> installedAfter(int seq) =>
      [for (final s in segments) if (s.removedAfterTruck == null || s.removedAfterTruck! > seq) s];

  double installedLengthAfter(int seq) => installedAfter(seq).fold(0.0, (a, s) => a + s.lengthM);

  /// Tremie bottom end after truck number [seq]: bottom − gap − what has been
  /// removed up to that truck.
  double tremieBottomAfter(int seq) {
    final removed = segments
        .where((s) => s.removedAfterTruck != null && s.removedAfterTruck! <= seq)
        .fold(0.0, (a, s) => a + s.lengthM);
    return geometry.bottomDepthM - bottomGapM - removed;
  }

  /// Average overbreak ratio of trucks sounded before & after.
  /// 1.0 if there are none yet. Clamped to 0.8–2.0: a single misread sounding
  /// must not make the next suggestion wild.
  double get averageRatio {
    final r = <double>[];
    for (final t in trucks) {
      final x = overbreakRatio(
        diameterMm: geometry.diameterMm,
        volumeM3: t.volumeM3,
        depthBeforeM: t.concreteBeforeM,
        depthAfterM: t.concreteAfterM,
      );
      if (x != null) r.add(x);
    }
    if (r.isEmpty) return 1.0;
    final avg = r.reduce((a, b) => a + b) / r.length;
    return avg.clamp(0.8, 2.0);
  }

  /// Rasio overbreak TM-TM SEBELUM [seq] di titik ini, yang sudah punya
  /// sounding sebelum dan sesudah.
  ///
  /// Dipakai sebagai PEMBANDING, bukan sebagai kebenaran: lubang boleh
  /// melebar, boleh menyempit (necking), dan tiap titik punya angkanya
  /// sendiri. Yang mencurigakan bukan angkanya tinggi atau rendah,
  /// melainkan angkanya MELOMPAT di tengah cor pada lubang yang sama.
  List<double> ratiosBefore(int seq) {
    final hasil = <double>[];
    for (final t in trucks) {
      if (t.seq >= seq) continue;
      final x = overbreakRatio(
        diameterMm: geometry.diameterMm,
        volumeM3: t.volumeM3,
        depthBeforeM: t.concreteBeforeM,
        depthAfterM: t.concreteAfterM,
      );
      if (x != null) hasil.add(x);
    }
    return hasil;
  }

  /// Concrete level after truck number [seq]: sounding if available, estimate otherwise.
  /// (seq 0 = hole bottom.) `measured` false = estimate.
  ({double depthM, bool measured}) concreteAfter(int seq) {
    var depth = geometry.bottomDepthM;
    var measured = true;
    final ratio = averageRatio;
    for (final t in trucks) {
      if (t.seq > seq) break;
      if (t.concreteBeforeM != null) {
        depth = t.concreteBeforeM!;
        measured = true;
      }
      if (t.concreteAfterM != null) {
        depth = t.concreteAfterM!;
        measured = true;
      } else {
        depth = math.max(
          geometry.cutOffDepthM,
          depth - t.volumeM3 * risePerM3(geometry.diameterMm, ratio: ratio),
        );
        measured = false;
      }
    }
    return (depthM: depth, measured: measured);
  }

  int get lastSeq => trucks.isEmpty ? 0 : trucks.last.seq;

  /// Concrete has reached cut-off after truck [seq]: the depth of the
  /// concrete level from GS is at or above the cut-off depth (half a
  /// centimetre of slack for rounding). Another truck is then usually not
  /// needed; a little over-pour above cut-off is normal and trimmed later.
  bool reachedCutOffAfter(int seq) => seq > 0 && concreteAfter(seq).depthM <= geometry.cutOffDepthM + 0.005;

  double get totalVolumeM3 => trucks.fold(0.0, (a, t) => a + t.volumeM3);

  /// Embedment length after truck number [seq].
  double embedmentAfter(int seq) => tremieBottomAfter(seq) - concreteAfter(seq).depthM;

  /// Overuse of concrete relative to the actual theoretical volume, percent.
  double? get overusePercent {
    final theoretical = geometry.actualTheoreticalVolumeM3 ?? geometry.plannedTheoreticalVolumeM3;
    if (theoretical <= 0 || trucks.isEmpty) return null;
    return (totalVolumeM3 / theoretical - 1) * 100;
  }

  /// Tremie length that reaches from the hopper level to the bottom gap.
  double get requiredTremieM => geometry.bottomDepthM - bottomGapM;

  /// Before the first truck, the tremie must reach the bottom (10 cm of
  /// slack): concrete poured from higher up drops through the slurry and
  /// segregates.
  bool get tremieReachesBottom => installedLengthAfter(0) >= requiredTremieM - 0.10;

  /// How far the assembled tremie stands above GS (to the hopper) when its
  /// lower end hangs at the bottom gap. Negative = still short of the bottom.
  double get tremieStickUpM => installedLengthAfter(0) - requiredTremieM;

  /// Stick-up after adding a piece of [lengthM].
  double stickUpWith(double lengthM) => tremieStickUpM + lengthM;

  /// Taller than a hopper can be reached: a segment too many, or a typo.
  bool get tremieTooLong => tremieStickUpM > tremieStickUpMaxM + 0.005;

  /// Concrete used up to truck [seq] against the theoretical volume of the
  /// hole filled so far, in percent over. Only from a MEASURED level (a
  /// sounding), and only once there is enough concrete to compare (0.5 m³).
  double? overuseSoFarPercent(int seq) {
    final level = concreteAfter(seq);
    if (!level.measured || seq <= 0) return null;
    final theoretical = geometry.areaM2 * (geometry.bottomDepthM - level.depthM);
    if (theoretical < 0.5) return null;
    final used = trucks.where((t) => t.seq <= seq).fold(0.0, (a, t) => a + t.volumeM3);
    return (used / theoretical - 1) * 100;
  }
}

/// A truck mixer in Indonesia carries 5–7 m³, a big one 8. Above this the
/// app asks once more; above [truckVolumeMaxM3] it refuses (a typo of 70 for 7).
/// Highest the tremie top (with the hopper) may stand above GS. Above this
/// the crew cannot reach the hopper, and in practice it means one segment
/// too many was entered.
const tremieStickUpMaxM = 3.0;

const truckVolumeUsualMaxM3 = 8.0;
const truckVolumeMaxM3 = 10.0;

/// Concrete used this much over theory, so far, gets a warning on screen:
/// the hole is probably wider than drilled (collapse, soft layer).
const overuseWarnPercent = 15.0;

/// Checked when a TM's volume is TYPED, before anything is poured.
///
/// Why here and not only after the sounding: by the time a sounding says the
/// pile has swallowed 70% more concrete than it should, the concrete is in
/// the ground. The cheapest moment to catch it is while the figure is still
/// a number on a screen.
///
/// The usual cause is NOT a wider hole. It is one TM shared between two
/// piles: the whole truck gets typed into both logs, so both read far over
/// theory. That is why the dialogs offer it as the first explanation.
const volumeWarnPercent = 10.0;

/// Past this the warning turns red — and that is ALL it does.
///
/// There was briefly a rule here that held the save button until a reason
/// was picked. It was wrong and came out the same day (Daniel, 12 Okt 2026):
/// overbreak past 100% genuinely happens in bad ground, so any ceiling is a
/// ceiling on the TRUTH. A foreman who cannot save what happened types a
/// smaller number so he can carry on — the one outcome worse than an
/// alarming figure that is correct.
///
/// What catches a real mistake is not a wall but a question, asked once,
/// after the sounding: see `_checkOveruseAfter`.
const volumeLoudPercent = 25.0;

/// Where this pile lands against theory if [addM3] more is poured, in
/// percent over (negative = still under). Null when there is no usable
/// theoretical volume.
double? overuseIfAdded({
  required double theoreticalM3,
  required double pouredSoFarM3,
  required double addM3,
}) {
  if (theoreticalM3 < 0.5) return null;
  return ((pouredSoFarM3 + addM3) / theoreticalM3 - 1) * 100;
}

class TremieSegment {
  const TremieSegment({
    required this.uuid,
    required this.position,
    required this.lengthM,
    this.removedAfterTruck,
    this.removedAt,
    this.isBottom = false,
  });

  final String uuid;

  /// The tremie bottom: the pointed end piece, always the lowest and never
  /// removed while casting. Its length is typed for every casting.
  final bool isBottom;
  final int position;
  final double lengthM;
  final int? removedAfterTruck;
  final String? removedAt;

  factory TremieSegment.fromJson(Map<String, Object?> j) => TremieSegment(
        uuid: '${j['uuid']}',
        position: toIntOrNull(j['position']) ?? 0,
        lengthM: toDoubleOrNull(j['lengthM']) ?? 0,
        removedAfterTruck: toIntOrNull(j['removedAfterTruckSeq']),
        removedAt: j['removedAt']?.toString(),
        isBottom: j['kind'] == 'bottom',
      );
}

class TruckRecord {
  const TruckRecord({required this.seq, required this.volumeM3, this.concreteBeforeM, this.concreteAfterM, this.start, this.end});

  final int seq;
  final double volumeM3;
  final double? concreteBeforeM;
  final double? concreteAfterM;
  final DateTime? start;
  final DateTime? end;

  factory TruckRecord.fromJson(Map<String, Object?> j) => TruckRecord(
        seq: toIntOrNull(j['seq']) ?? 0,
        volumeM3: toDoubleOrNull(j['volumeM3']) ?? 0,
        concreteBeforeM: toDoubleOrNull(j['concreteDepthBeforeM']),
        concreteAfterM: toDoubleOrNull(j['concreteDepthAfterM']),
        start: j['startAt'] == null ? null : DateTime.tryParse('${j['startAt']}'),
        end: j['endAt'] == null ? null : DateTime.tryParse('${j['endAt']}'),
      );
}

/// Why a sounding AFTER a truck cannot be right, or null when it can.
///
/// Concrete only rises while pouring, so the level after a truck is never
/// DEEPER than the level before it (10 cm of slack for the tape), and never
/// below the hole bottom.
String? soundingProblem(double afterM, {required double before, required double bottom}) {
  // Pure logic with a sentence attached: the message is read from the
  // language the app is showing, falling back to Indonesian when there is no
  // screen yet (tests, the background isolate). The RULE never depends on it.
  final l = L10n.current;
  if (afterM > bottom + 0.05) {
    final b = bottom.toStringAsFixed(2).replaceAll('.', ',');
    return l?.soundDeeperThanBottom(b) ?? 'Lebih dalam dari dasar lubang ($b m). Periksa lagi.';
  }
  if (afterM > before + 0.10) {
    final b = before.toStringAsFixed(2).replaceAll('.', ',');
    return l?.soundDeeperThanBefore(b) ??
        'Lebih dalam dari muka beton sebelum TM ini ($b m). Beton tidak mungkin turun; periksa lagi.';
  }
  return null;
}

/// Sejauh mana rasio satu TM boleh berbeda dari pola titiknya sendiri.
///
/// DIMINTA DANIEL, 27 Okt 2026, dari kejadian nyata: satu titik berjalan
/// 1,04 · 1,04 · 1,05 lalu tiba-tiba 0,50 — dan 0,50 itu ternyata salah
/// ketik sounding, bukan lubangnya yang berubah.
///
/// KENAPA PEMBANDINGNYA POLA TITIK ITU, BUKAN ANGKA TETAP
///
/// Lubang boleh melebar, dan boleh juga menyempit — necking memang ada.
/// Jadi tidak ada satu angka benar yang berlaku untuk semua titik: yang
/// 1,30 sepanjang cor itu wajar, dan yang 0,90 sepanjang cor juga wajar.
/// Yang TIDAK wajar adalah angkanya melompat di tengah pengecoran pada
/// lubang yang sama, sebab lubangnya sudah selesai dibor sebelum beton
/// pertama masuk — bentuknya tidak berubah lagi di tengah jalan.
const ratioDeviationMax = 0.20;

/// Batas kewarasan saat belum ada pembanding sama sekali (TM pertama).
///
/// Angkanya SAMA dengan clamp di `averageRatio`, dan memang harus sama:
/// dua definisi "wajar" yang berbeda di satu berkas akan berselisih suatu
/// saat, dan yang membacanya tidak punya cara tahu mana yang berlaku.
const ratioFloor = 0.80;
const ratioCeiling = 2.00;

/// Rasio TM ini mencurigakan atau tidak.
///
/// Mengembalikan null bila wajar. Bila tidak, [pembanding] adalah median
/// rasio TM sebelumnya — median, bukan rata-rata, supaya SATU angka buruk
/// yang terlanjur tersimpan tidak menggeser pembandingnya dan menutupi
/// angka berikutnya. Null pada [pembanding] berarti belum ada TM
/// pembanding dan yang dipakai batas kewarasan di atas.
({double? pembanding, List<double> sebelumnya})? overbreakOddity({
  required double ratio,
  required List<double> sebelumnya,
}) {
  if (sebelumnya.isEmpty) {
    if (ratio < ratioFloor || ratio > ratioCeiling) {
      return (pembanding: null, sebelumnya: const []);
    }
    return null;
  }
  final urut = [...sebelumnya]..sort();
  final t = urut.length ~/ 2;
  final median = urut.length.isOdd ? urut[t] : (urut[t - 1] + urut[t]) / 2;
  if (median <= 0) return null;
  if ((ratio - median).abs() / median > ratioDeviationMax) {
    return (pembanding: median, sebelumnya: sebelumnya);
  }
  return null;
}

/// Finishing a pile this far below cut-off counts as finished: the small
/// over-pour above cut-off is trimmed off anyway, and a few centimetres under
/// it is within the trim.
const cutOffSlackM = 0.5;

/// Usual truck volume, for turning a missing volume into "how many TM lagi"
/// when this pile has no truck recorded yet.
const truckVolumeTypicalM3 = 7.0;

/// What is still missing to reach cut-off, for the "Selesai cor" confirmation.
///
/// [missingM] is how far the concrete surface still is BELOW cut-off (positive
/// = short). Metres alone do not warn anybody — "kurang 10,40 m" reads as a
/// number, "±4 TM lagi" reads as a mistake — so the shortfall is also given as
/// a volume and as truckloads, using this pile's own average truck when it has
/// one.
///
/// [mustExplain] is the gate on closing the pile short: beyond [cutOffSlackM]
/// the screen asks for a reason instead of offering a one-tap "Tetap selesai".
({double volumeM3, int trucks, bool mustExplain}) shortfallToCutOff({
  required double missingM,
  required double areaM2,
  double? averageTruckM3,
}) {
  if (missingM <= 0) return (volumeM3: 0, trucks: 0, mustExplain: false);
  final volume = areaM2 * missingM;
  final per = (averageTruckM3 == null || averageTruckM3 <= 0) ? truckVolumeTypicalM3 : averageTruckM3;
  return (
    volumeM3: volume,
    trucks: (volume / per).ceil(),
    mustExplain: missingM > cutOffSlackM,
  );
}
