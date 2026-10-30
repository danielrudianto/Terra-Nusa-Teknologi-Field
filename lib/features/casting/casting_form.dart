import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/device/camera.dart';
import '../../core/device/notifications.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/reasons.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/number_dialog.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/blocked_action.dart';
import '../../core/widgets/step_progress.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/time_wheel.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/status_badge.dart';
import '../attendance/review_badge.dart';
import '../drilling/drill_readings.dart';
import 'calc/casting_state.dart';
import 'calc/cut_plan.dart';
import 'calc/pauses.dart';
import 'calc/pile_snapshot.dart';
import 'calc/volume.dart';
import 'measure_diagram.dart';
import 'concrete_suppliers.dart';
import 'handover.dart';
import 'pile_section_view.dart';
import 'tremie_string_view.dart';
import '../../core/i18n.dart';

/// Casting log for one pile point.
///
/// DOCUMENT CONTENT = EXACTLY `DataCor` ON THE SERVER
///
///   pilePointUuid, date, concreteGrade, supplierID, supplierName,
///   tremieBottomGapM, status, note, tremie[...], trucks[...]
///
/// `supplierID` DAN `supplierName` SELALU KOSONG, jangan dibaca. Keduanya
/// masih ada supaya APK lama tidak ditolak server, dan akan dibuang begitu
/// seluruh HP memakai 1.0.15 ke atas. Pemasok yang benar ada di tiap
/// `trucks[]`, dan hanya di situ — dua tempat untuk satu hal sudah pernah
/// berselisih di sini.
///
/// WORK ORDER IN THE FIELD — and the order of this screen
///
///   1. Assemble the tremie (bottom segment → top).
///   2. TM arrives: enter truck no., ticket, volume, slump, ticket photo.
///      The app computes the cut PLAN for that TM.
///   3. Start casting the TM → stopwatch (also in the notification).
///   4. Remove a segment mid-TM if the plan calls for it: tick it.
///   5. Finish TM → sound the concrete level → cut suggestion → tick.
///   6. Repeat 2–5. Last: Finish casting.
///
/// Every step is saved immediately (and goes into the send queue).
class CastingForm extends ConsumerStatefulWidget {
  const CastingForm({super.key, required this.uuid, this.pilePointUuid});

  final String uuid;

  /// Filled in when a NEW casting log is created from the point list.
  final String? pilePointUuid;

  @override
  ConsumerState<CastingForm> createState() => _CastingFormState();
}

class _CastingFormState extends ConsumerState<CastingForm> {
  Map<String, Object?>? _doc;
  Map<String, Object?>? _pilePoint;
  Map<String, Object?>? _project;
  double? _localDrillDepth;

  /// GS from the latest drill mark on this phone, else the server's. Never
  /// null once loaded: the screen refuses to open without it.
  double? _groundLevel;
  DocumentRow? _row;
  bool _isNew = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _runningTruck != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final rows = await db.getDocument(widget.uuid);
    Map<String, Object?>? doc;
    String? pilePointUuid = widget.pilePointUuid;
    if (rows != null) {
      doc = (jsonDecode(rows.body) as Map).cast<String, Object?>();
      pilePointUuid = '${doc['pilePointUuid']}';
    }
    if (pilePointUuid == null) {
      setState(() => _error = t(context).castLogNotOnPhone);
      return;
    }
    final pilePoint = await db.getMaster('pile_point', pilePointUuid);
    if (pilePoint == null) {
      setState(() => _error = t(context).pointNotOnPhone);
      return;
    }
    final project = await db.getMaster('project', '${pilePoint['projectID']}');

    // Drilled depth on the phone that may not have reached the server yet:
    // the latest drill mark, or a finished drill log, whichever is newer.
    final p = ref.read(userProvider);
    double? localDrillDepth;
    double? localGroundLevel;
    if (p != null) {
      DateTime? newest;
      final drillMarks = await db.watchDocuments('drill_mark', p.id).first;
      for (final d in drillMarks) {
        final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
        if ('${body['pilePointUuid']}' == pilePointUuid && d.sendStatus != 'rejected') {
          localDrillDepth = toDoubleOrNull(body['drilledDepthM']);
          localGroundLevel = toDoubleOrNull(body['groundLevel']);
          newest = d.updatedAt;
          break;
        }
      }
      final drillLogs = await db.watchDocuments('drill_log', p.id).first;
      for (final d in drillLogs) {
        final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
        if ('${body['pilePointUuid']}' != pilePointUuid || d.sendStatus == 'rejected' || body['status'] != 'selesai') continue;
        if (newest == null || d.updatedAt.isAfter(newest)) {
          localDrillDepth = deepestM(readingsOf(body)) ?? localDrillDepth;
          localGroundLevel = toDoubleOrNull(body['groundLevel']) ?? localGroundLevel;
        }
        break;
      }
    }
    // Every depth on this screen is measured from GS. Without it the tremie,
    // cut-off and sounding figures would all be computed from a made-up 0,
    // and the server refuses a new casting anyway (GS_KOSONG).
    final groundLevel = localGroundLevel ?? toDoubleOrNull(pilePoint['groundLevel']);
    if (groundLevel == null) {
      setState(() => _error = t(context).gsMissingFor('${pilePoint['code']}'));
      return;
    }

    // One point, one casting log: the server refuses a second one.
    final existing = pilePoint['castingUuid'];
    if (doc == null && existing != null && '$existing' != widget.uuid) {
      setState(() => _error = t(context).pointHasCastLog(
            '${pilePoint['code']}',
            pilePoint['castingByName'] == null ? '' : t(context).byWhom('${pilePoint['castingByName']}'),
          ));
      return;
    }

    // A new log needs the drilled depth too (the hole bottom). The point list
    // disables "Mulai log cor" until then; this catches any other way in.
    if (doc == null && localDrillDepth == null && toDoubleOrNull(pilePoint['drilledDepthM']) == null) {
      setState(() => _error = t(context).pointNotDrilled('${pilePoint['code']}'));
      return;
    }

    if (doc == null) {
      _isNew = true;
      doc = {
        'pilePointUuid': pilePointUuid,
        'date': isoDate(DateTime.now()),
        'concreteGrade': null,
        'supplierID': null,
        'supplierName': null,
        'tremieBottomGapM': '1.00',
        'status': 'berjalan',
        'note': null,
        'tremie': <Object?>[],
        'trucks': <Object?>[],
        'pauses': <Object?>[],
      };
    }
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _row = rows;
      _pilePoint = pilePoint;
      _project = project;
      _localDrillDepth = localDrillDepth;
      _groundLevel = groundLevel;
    });
  }

  // -------------------------------------------------------------------------
  // Derived
  // -------------------------------------------------------------------------

  PileGeometry get _geometry => PileGeometry(
        diameterMm: toIntOrNull(_pilePoint!['diameterMm']) ?? 0,
        groundLevel: _groundLevel!,
        cutOffLevel: toDoubleOrNull(_pilePoint!['cutOffLevel']) ?? 0,
        tipLevel: toDoubleOrNull(_pilePoint!['tipLevel']) ?? 0,
        drilledDepthM: _localDrillDepth ?? toDoubleOrNull(_pilePoint!['drilledDepthM']),
      );

  CastingState get _castingState => CastingState.from(_geometry, _doc!);

  List<Map<String, Object?>> get _tremie => [for (final s in (_doc!['tremie'] as List)) (s as Map).cast<String, Object?>()];
  /// Stopwatch pauses. Older documents on the phone have no `pauses` key.
  List<Map<String, Object?>> get _pauses =>
      [for (final p in (_doc!['pauses'] as List? ?? const [])) (p as Map).cast<String, Object?>()];
  List<Map<String, Object?>> get _trucks => [for (final t in (_doc!['trucks'] as List)) (t as Map).cast<String, Object?>()];

  /// Pemasok yang BENAR-BENAR menuang titik ini, dibaca dari TM-nya.
  ///
  /// Satu titik boleh disuapi dua batching plant, jadi jawabannya memang
  /// bisa lebih dari satu nama — dan itu justru yang perlu terlihat.
  /// Digabung dengan " + ", sama dengan rekap Excel di kantor, supaya layar
  /// dan kertas tidak menyebut hal berbeda untuk titik yang sama.
  ///
  /// DITURUNKAN, tidak disimpan. Satu nilai pemasok yang disimpan terpisah
  /// dari TM-nya adalah tempat kedua yang akan berselisih dengan TM-nya
  /// sendiri — itu persis kesalahan yang baru saja dicabut.
  String? get _suppliersFromTrucks {
    final urut = [..._trucks]..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0));
    final nama = <String>[];
    for (final t in urut) {
      final n = t['supplierName']?.toString().trim();
      if (n == null || n.isEmpty || nama.contains(n)) continue;
      nama.add(n);
    }
    return nama.isEmpty ? null : nama.join(' + ');
  }

  Map<String, Object?>? get _lastTruck {
    final d = _trucks;
    if (d.isEmpty) return null;
    d.sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0));
    return d.last;
  }

  Map<String, Object?>? get _runningTruck {
    final t = _doc == null ? null : _lastTruck;
    return t != null && t['startAt'] != null && t['endAt'] == null ? t : null;
  }

  /// Effective grade: casting log entry → point → project.
  double? get _grade =>
      toDoubleOrNull(_doc!['concreteGrade']) ?? toDoubleOrNull(_pilePoint!['concreteGrade']) ?? toDoubleOrNull(_project?['defaultConcreteGrade']);

  bool get _locked => _row?.serverStatus == 'diperiksa';
  bool get _finished => _doc!['status'] == 'selesai';

  /// Handed over (Oper): the server names someone else as holder of THIS log,
  /// so this phone only looks on — its pushes would be refused (DIOPER).
  ///
  /// The holder on the point describes the casting the SERVER has for that
  /// point. If that is not this document (another phone logged the point, or
  /// this log has never been pushed), it says NOTHING about this log — reading
  /// it as a handover would lock a perfectly normal log read-only, and every
  /// save would then do nothing.
  bool get _handedAway {
    if (_row == null) return false;
    final serverUuid = _pilePoint?['castingUuid'];
    if (serverUuid == null || '$serverUuid' != widget.uuid) return false;
    final holder = toIntOrNull(_pilePoint?['castingHolderID']);
    final me = ref.read(userProvider)?.id;
    return holder != null && me != null && holder != me;
  }

  String? get _holderName => _pilePoint?['castingHolderName']?.toString();

  /// Rekan yang menunggu jawaban atas permintaan opernya, bila ada.
  String? get _peminta {
    if (_handedAway) return null;
    final siapa = toIntOrNull(_pilePoint?['castingRequestBy']);
    final me = ref.read(userProvider)?.id;
    if (siapa == null || me == null || siapa == me) return null;
    return _pilePoint?['castingRequestName']?.toString() ?? t(context).colleague;
  }

  /// Setujui atau tolak. Disetujui = log ini bukan milik HP ini lagi, jadi
  /// layarnya ditutup; membiarkannya terbuka berarti orangnya terus mengetik
  /// TM ke log yang setiap simpanannya akan ditolak server.
  Future<void> _jawabOper(bool setuju) async {
    final siapa = _peminta;
    if (siapa == null) return;
    final pindah = await answerHandoverFlow(
      context,
      ref,
      entity: 'casting',
      uuid: widget.uuid,
      pointCode: '${_pilePoint!['code']}',
      requesterName: siapa,
      agree: setuju,
    );
    if (!mounted) return;
    if (pindah) {
      context.pop();
    } else {
      await _load();
    }
  }

  /// Nothing on this screen may change the document.
  bool get _readOnly => _locked || _handedAway;

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  /// Change and save the document. Returns FALSE when nothing was written.
  ///
  /// A caller must never report success on its own: a screen that is locked or
  /// handed over writes nothing, and a silent `return` here used to leave the
  /// caller showing its "saved" dialog and snackbar over unchanged data.
  Future<bool> _update(void Function(Map<String, Object?> d) f) async {
    if (_readOnly) {
      if (mounted) showSnack(context, _readOnlyReason, icon: Icons.lock_outline);
      return false;
    }
    final p = ref.read(userProvider);
    if (p == null) {
      if (mounted) showSnack(context, t(context).notSignedIn, icon: Icons.error_outline);
      return false;
    }
    setState(() => f(_doc!));
    final db = ref.read(dbProvider);
    await db.saveDocument(uuid: widget.uuid, entity: 'casting', userId: p.id, body: _doc!);
    _row = await db.getDocument(widget.uuid);
    _isNew = false;
    ref.read(syncProvider.notifier).afterSave();
    if (mounted) setState(() {});
    return true;
  }

  /// Why this screen cannot be changed — shown instead of a fake success.
  String get _readOnlyReason => _locked
      ? t(context).lockedByOffice
      : t(context).heldByOther(_holderName ?? t(context).colleague);

  // -------------------------------------------------------------------------
  // Tremie
  // -------------------------------------------------------------------------

  /// Add a tremie piece, unless it would stand the tremie top higher above
  /// GS than a hopper can be reached ([tremieStickUpMaxM]).
  Future<void> _addSegment(double lengthM, {bool bottom = false}) async {
    final k = _castingState;
    final stickUp = k.stickUpWith(lengthM);
    if (stickUp > tremieStickUpMaxM + 0.005) {
      await _block(
        icon: Icons.height,
        title: t(context).tremieTooLongTitle,
        body: t(context).tremieTooLongAdd(_decimal(lengthM), formatMeters(stickUp),
            formatMeters(tremieStickUpMaxM), formatMeters(k.requiredTremieM)),
      );
      return;
    }
    await _appendSegment(lengthM, bottom: bottom);
  }

  Future<void> _appendSegment(double lengthM, {bool bottom = false}) => _update((d) {
        final s = _tremie;
        final position = s.isEmpty ? 1 : s.map((x) => toIntOrNull(x['position']) ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        (d['tremie'] as List).add({
          'uuid': newUuid(),
          'position': position,
          'lengthM': decimalText(lengthM),
          // The pointed end piece; always first, so always position 1.
          'kind': bottom ? 'bottom' : 'section',
          'removedAfterTruckSeq': null,
          'removedAt': null,
        });
      });

  Future<void> _addBottom() async {
    final v = (await _askNumber(
      title: t(context).tremieBottomTitle,
      label: t(context).lengthM,
      icon: Icons.change_history,
      suffix: 'm',
      maxValue: 12,
      hint: t(context).tremieBottomHint,
    ))
        ?.$1;
    if (v != null) await _addSegment(v, bottom: true);
  }

  Future<void> _removeTopSegment() async {
    if (_tremie.isEmpty) return;
    final saved = await _update((d) {
      final s = _tremie..sort((a, b) => (toIntOrNull(a['position']) ?? 0).compareTo(toIntOrNull(b['position']) ?? 0));
      final top = s.last;
      (d['tremie'] as List).removeWhere((x) => (x as Map)['uuid'] == top['uuid']);
    });
    if (saved && mounted) showSnack(context, t(context).topSegmentRemoved);
  }

  Future<void> _customSegment() async {
    final v = (await _askNumber(title: t(context).segmentLength, label: t(context).lengthM, icon: Icons.straighten, suffix: 'm', maxValue: 12))?.$1;
    if (v != null) await _addSegment(v);
  }

  /// A stop the user cannot pass: one button, nothing to override.
  Future<void> _block({required IconData icon, required String title, required String body}) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(icon, size: 32, color: c.colors.badFg),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(body, style: TextStyle(color: c.colors.ink, height: 1.4)),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c).understood))],
        ),
      );

  /// Tick a segment as removed, unless that leaves less than 1 m of tremie in
  /// the concrete. From a sounded level that is a hard stop; from an
  /// estimate the QS may go on after a warning, since the estimate can be off.
  /// Tandai/batalkan satu segmen tremie sebagai TERCABUT.
  ///
  /// [tanya] hanya dinyalakan dari DAFTAR tremie — satu ketukan di daftar
  /// itulah yang menulis `removedAt` tanpa pertanyaan apa pun. Dua jalur
  /// lainnya (`_askPullTremie` sesudah TM beres, dan tombol pada kartu
  /// saran) SUDAH bertanya; menanyai orang dua kali di satu tindakan hanya
  /// melatihnya menekan "ya" tanpa membaca.
  ///
  /// Dilaporkan Daniel, 16 Okt 2026 pada SP.B41: dua segmen bertanda
  /// dicabut jam 18:56 dan 19:17, sementara penuangan TM terakhir selesai
  /// 18:51. Keduanya tidak pernah benar-benar dicabut — panjang tremie yang
  /// tercatat per TM membuktikannya — dan membetulkannya butuh SQL.
  Future<void> _toggleRemoved(String segmentUuid, int? seq, {bool tanya = false}) async {
    if (seq != null) {
      final k = _castingState;
      final seg = k.segments.where((s) => s.uuid == segmentUuid).firstOrNull;
      final snap = _snapshotNow(k);
      final after = snap.tremieBottomM - (seg?.lengthM ?? 0) - snap.concreteNowM;
      const limits = EmbedmentLimits();
      if (seg != null && after < limits.minimumM) {
        final text = t(context).embedAfterRemoval(
            _decimal(seg.lengthM), formatMeters(math.max(after, 0)), formatMeters(limits.minimumM));
        if (snap.concreteMeasured) {
          await _block(icon: Icons.dangerous_outlined, title: t(context).dontPullYet, body: text);
          return;
        }
        final goOn = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: Icon(Icons.warning_amber_rounded, size: 32, color: c.colors.warnFg),
            title: Text(t(c).embedTooShortTitle, textAlign: TextAlign.center),
            content: Text(t(c).estimateSoundFirst(text), style: TextStyle(color: c.colors.ink, height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).tickAnyway, style: TextStyle(color: c.colors.badFg))),
              FilledButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).cancel)),
            ],
          ),
        );
        if (goOn != true) return;
      }
    }
    if (tanya && seq != null) {
      // Penjaga sesudah `await` di atas: cabang "tertanam terlalu pendek"
      // sudah membuka dialognya sendiri, jadi layarnya bisa sudah ditutup
      // orangnya saat eksekusi kembali ke sini. `context` yang dipakai
      // sesudah itu menunjuk widget yang tidak ada lagi.
      if (!mounted) return;
      final seg = _castingState.segments.where((x) => x.uuid == segmentUuid).firstOrNull;
      if (seg != null) {
        final snap = _snapshotNow(_castingState);
        final sisa = snap.tremieBottomM - seg.lengthM - snap.concreteNowM;
        // TM itu sudah SELESAI dituang: tidak ada tremie yang sedang
        // bergerak, jadi cabutan yang ditandai sekarang hampir pasti
        // ketukan beres-beres. Dibuat `danger` supaya tombolnya tidak
        // berada di tempat yang biasa ditekan tanpa dibaca.
        final tm = _trucks.where((x) => toIntOrNull(x['seq']) == seq).firstOrNull;
        final sudahSelesai = tm?['endAt'] != null;
        final setuju = await askConfirm(
          context,
          icon: Icons.north,
          danger: sudahSelesai,
          title: t(context).pullTickTitle,
          body: [
            t(context).pullTickBody(
              seg.position,
              _decimal(seg.lengthM),
              seq,
              formatMeters(math.max(sisa, 0)),
            ),
            if (sudahSelesai) t(context).pullTickAfterPour(seq),
          ].join('\n\n'),
          confirmLabel: t(context).pulledAlready,
        );
        if (!setuju) return;
      }
    }
    await _setRemoved(segmentUuid, seq);
    if (mounted) {
      showSnack(context, seq == null ? t(context).pullUndone : t(context).pullRecorded(seq));
    }
  }

  Future<void> _setRemoved(String segmentUuid, int? seq) => _update((d) {
        for (final x in (d['tremie'] as List)) {
          final m = x as Map;
          if (m['uuid'] == segmentUuid) {
            m['removedAfterTruckSeq'] = seq;
            m['removedAt'] = seq == null ? null : isoWithOffset(DateTime.now());
          }
        }
      });

  // -------------------------------------------------------------------------
  // TM
  // -------------------------------------------------------------------------

  Future<void> _newTruck() async {
    final unsounded = _unsoundedTruck;
    if (unsounded != null && !await _askSoundingAfter(unsounded)) return;
    final k = _castingState;
    final seq = k.lastSeq + 1;
    if (k.reachedCutOffAfter(seq - 1) && !await _confirmTruckAboveCutOff(k, seq - 1)) return;
    // Supplier of THIS truck: one pile may be fed by two batching plants.
    // Prefilled from the previous TM, so the common case (one plant all
    // day) costs no extra tap.
    //
    // TIDAK LAGI mundur ke `_doc` — pemasok per titik sudah dipensiunkan.
    // Log cor dulu menyimpan pemasoknya sendiri di kepala, terpisah dari
    // pemasok tiap TM, dan keduanya berselisih tanpa satu pun galat: 26
    // Okt 2026 seluruh TM datang dari Adhimix sementara kepalanya menyebut
    // Jayamix. Kepala itu kini selalu kosong; membacanya hanya akan
    // menyodorkan nama dari dokumen lama sebagai tawaran awal.
    final lastTruck = _trucks.lastOrNull;
    final defaultSupplierId = toIntOrNull(lastTruck?['supplierID']);
    final defaultSupplierName = lastTruck?['supplierName']?.toString();
    final offer = suppliersForProject(
      await ref.read(dbProvider).listMaster('supplier'),
      toIntOrNull(_pilePoint!['projectID']),
      keepId: defaultSupplierId,
    );
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _TruckSheet(
        seq: seq,
        estimatedConcreteBefore: k.concreteAfter(seq - 1).depthM,
        theoreticalM3: k.geometry.actualTheoreticalVolumeM3 ?? k.geometry.plannedTheoreticalVolumeM3,
        pouredSoFarM3: k.totalVolumeM3,
        takeTicketPhoto: _takeTicketPhoto,
        suppliers: offer.suppliers,
        suppliersNarrowed: offer.narrowed,
        supplierId: defaultSupplierId,
        supplierName: defaultSupplierName,
      ),
    );
    if (result == null) return;
    // The next truck is here: no more waiting reminders.
    await Notifications.cancelIdleReminders();
    final saved = await _update((d) {
      (d['trucks'] as List).add({
        'uuid': newUuid(),
        'seq': seq,
        'truckNo': result['truckNo'],
        'supplierID': result['supplierID'],
        'supplierName': result['supplierName'],
        'arrivedAt': isoWithOffset(DateTime.now()),
        'slumpCm': result['slumpCm'],
        'volumeM3': result['volumeM3'],
        'startAt': null,
        'startEdited': false,
        'endAt': null,
        'endEdited': false,
        // Tremie length installed when this TM starts — derived from the
        // segments, not retyped.
        'tremieLengthM': decimalText(k.installedLengthAfter(seq - 1)),
        'concreteDepthBeforeM': result['concreteDepthBeforeM'],
        'concreteDepthAfterM': null,
        'ticketPhotoUuid': result['ticketPhotoUuid'],
        'slumpPhotoUuid': result['slumpPhotoUuid'],
        'note': null,
      });
    });
    if (!saved) return;
    if (mounted) showSnack(context, t(context).truckSaved(seq), icon: Icons.local_shipping_outlined);
  }

  /// Correct a TM that was typed wrong — slump, volume, hull number,
  /// supplier, photos.
  ///
  /// Everything else about a TM can already be fixed by tapping its row
  /// (times, soundings); these five could only be typed once, so a slump of
  /// 8 entered as 18 was stuck in the quality record for good and the only
  /// way out was the office deleting the whole casting log. The sheet that
  /// enters a TM is the same sheet that corrects it, so the rules cannot
  /// drift apart.
  Future<void> _editTruck(Map<String, Object?> truck) async {
    if (_readOnly) return;
    final k = _castingState;
    final seq = toIntOrNull(truck['seq']) ?? 0;
    final supplierId = toIntOrNull(truck['supplierID']);
    final offer = suppliersForProject(
      await ref.read(dbProvider).listMaster('supplier'),
      toIntOrNull(_pilePoint!['projectID']),
      // A supplier dropped from the project's POs since must still show, or
      // reopening an old TM would silently change who delivered it.
      keepId: supplierId,
    );
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _TruckSheet(
        seq: seq,
        initial: truck,
        estimatedConcreteBefore: k.concreteAfter(seq - 1).depthM,
        theoreticalM3: k.geometry.actualTheoreticalVolumeM3 ?? k.geometry.plannedTheoreticalVolumeM3,
        // TANPA truk yang sedang dikoreksi: angkanya sedang diketik ulang,
        // jadi menghitungnya dua kali akan menuduh mandor berlebihan.
        pouredSoFarM3: k.totalVolumeM3 - (toDoubleOrNull(truck['volumeM3']) ?? 0),
        takeTicketPhoto: _takeTicketPhoto,
        suppliers: offer.suppliers,
        suppliersNarrowed: offer.narrowed,
        supplierId: supplierId,
        supplierName: truck['supplierName']?.toString(),
      ),
    );
    if (result == null) return;
    final saved = await _updateTruck('${truck['uuid']}', (t) {
      t['truckNo'] = result['truckNo'];
      t['supplierID'] = result['supplierID'];
      t['supplierName'] = result['supplierName'];
      t['slumpCm'] = result['slumpCm'];
      t['volumeM3'] = result['volumeM3'];
      t['concreteDepthBeforeM'] = result['concreteDepthBeforeM'];
      t['ticketPhotoUuid'] = result['ticketPhotoUuid'];
      t['slumpPhotoUuid'] = result['slumpPhotoUuid'];
    });
    if (saved && mounted) showSnack(context, t(context).truckUpdated(seq), icon: Icons.edit_outlined);
  }

  /// Warn before another truck when the concrete is already at cut-off.
  /// Returns true to add the truck anyway.
  Future<bool> _confirmTruckAboveCutOff(CastingState k, int lastSeq) async {
    final level = k.concreteAfter(lastSeq);
    final over = k.geometry.cutOffDepthM - level.depthM;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) {
        final w = c.colors;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, size: 32, color: w.warnFg),
          title: Text(t(c).atCutOffTitle, textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(c).atCutOffBody(
                  formatMeters(level.depthM),
                  formatMeters(k.geometry.cutOffDepthM),
                  over > 0.005 ? t(c).overBy(formatMeters(over)) : '',
                ),
                style: TextStyle(color: w.ink, height: 1.4),
              ),
              if (!level.measured) ...[
                const SizedBox(height: 10),
                Text(
                  t(c).estimateFromVolume,
                  style: TextStyle(color: w.warnFg, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'finish'), child: Text(t(c).finishCasting)),
            FilledButton(onPressed: () => Navigator.pop(c, 'add'), child: Text(t(c).addTruckAnyway)),
          ],
        );
      },
    );
    if (choice == 'finish') await _finishCasting();
    return choice == 'add';
  }

  Future<String?> _takeTicketPhoto() async {
    final p = ref.read(userProvider);
    if (p == null) return null;
    final f = await takePhoto(db: ref.read(dbProvider), userId: p.id, kind: 'tiket_tm');
    return f?.uuid;
  }

  // ---------------------------------------------------------------------
  // FOTO SLUMP DICABUT — 19 Oktober 2026, permintaan Daniel
  // ---------------------------------------------------------------------
  //
  // Dulu di sini ada `_takeSlumpPhoto` beserta seluruh alur "foto duluan":
  // uji slump TM berikutnya biasa dilakukan saat TM sekarang masih dituang,
  // jadi fotonya diparkir di `meta` lokal sampai TM-nya dibuka.
  //
  // Semuanya dibuang. ANGKA slump (`slumpCm`) tetap dicatat seperti biasa —
  // yang hilang hanya fotonya.
  //
  // Titipan yang mungkin masih tersimpan di HP dari versi sebelumnya
  // sengaja TIDAK disapu: kuncinya (`slump_menunggu:<uuid log>`) tidak
  // pernah dibaca lagi, isinya beberapa puluh karakter, dan menulis kode
  // pembersih untuk sesuatu yang tidak dibaca siapa pun hanya menambah kode
  // yang kelak membingungkan.

  Future<bool> _updateTruck(String truckUuid, void Function(Map<Object?, Object?> t) f) => _update((d) {
        for (final x in (d['trucks'] as List)) {
          final m = x as Map;
          if (m['uuid'] == truckUuid) f(m);
        }
      });

  /// Project · point, for the notification header.
  ///
  /// The point row carries `projectID`, not the code, so the code is looked
  /// up in the pulled project list — and simply left out when that list is
  /// not on the phone yet.
  String get _notifSubText {
    final id = '${_pilePoint?['projectID']}';
    final project = (ref.read(projectsProvider).value ?? const <Map<String, Object?>>[])
        .where((p) => '${p['id']}' == id)
        .firstOrNull;
    return [
      if (project?['code'] != null) '${project!['code']}',
      'Titik ${_pilePoint!['code']}',
    ].join(' · ');
  }

  /// How far the concrete has climbed from the hole bottom toward cut-off,
  /// 0–100. This is what the QS is actually waiting for, so it is the bar.
  ///
  /// Null before anything is poured or when the geometry cannot say — a bar
  /// stuck at zero reads as "nothing is happening", which is worse than no
  /// bar at all.
  int? get _notifProgress {
    final k = _castingState;
    final bottom = k.geometry.bottomDepthM;
    final cutOff = k.geometry.cutOffDepthM;
    final span = bottom - cutOff;
    if (span <= 0) return null;
    final now = k.concreteAfter(k.lastSeq).depthM;
    final done = ((bottom - now) / span * 100).round();
    return done <= 0 ? null : done.clamp(0, 100);
  }

  /// The lines shown when the notification is pulled open.
  String _notifDetail(Map<String, Object?> truck) {
    final k = _castingState;
    final level = k.concreteAfter(k.lastSeq);
    return [
      'TM #${truck['seq']} · ${_decimal(truck['volumeM3'])} m³',
      'Terpakai ${_decimal(k.totalVolumeM3)} m³ dari ${_decimal(k.geometry.actualTheoreticalVolumeM3 ?? k.geometry.plannedTheoreticalVolumeM3)} m³ teoritis',
      'Muka beton ${formatMeters(level.depthM)}${level.measured ? '' : ' (perkiraan)'} · cut-off ${formatMeters(k.geometry.cutOffDepthM)}',
    ].join('\n');
  }
  Future<void> _startTruck(Map<String, Object?> truck) async {
    final k = _castingState;
    if ((toIntOrNull(truck['seq']) ?? 0) == 1 && k.tremieTooLong) {
      await _block(
        icon: Icons.height,
        title: t(context).tremieTooLongTitle,
        body: t(context).tremieTooLongNow(formatMeters(k.installedLengthAfter(0)), formatMeters(k.tremieStickUpM),
            formatMeters(tremieStickUpMaxM), formatMeters(k.requiredTremieM)),
      );
      return;
    }
    if ((toIntOrNull(truck['seq']) ?? 0) == 1 && !k.tremieReachesBottom) {
      await _block(
        icon: Icons.vertical_align_bottom,
        title: t(context).tremieNotAtBottom,
        body: t(context).tremieShortBody(formatMeters(k.installedLengthAfter(0)), formatMeters(k.requiredTremieM)),
      );
      return;
    }
    // Terjemahan diambil SEBELUM await: sesudahnya layar bisa saja sudah
    // ditutup, dan `context` tidak boleh dipakai lagi.
    final l = t(context);
    await Notifications.cancelIdleReminders();
    final start = DateTime.now();
    if (!await _updateTruck('${truck['uuid']}', (t) => t['startAt'] = isoWithOffset(start))) return;
    await Notifications.requestPermission();
    await Notifications.showStopwatch(
      route: '/casting/log/${widget.uuid}',
      title: l.notifPouring('${truck['seq']}'),
      body: l.notifTapToOpen(_decimal(truck['volumeM3'])),
      start: start,
      subText: _notifSubText,
      detail: _notifDetail(truck),
      progress: _notifProgress,
    );
    await _scheduleReminder(truck, poured: Duration.zero);
    if (mounted) showSnack(context, l.pourStarted('${truck['seq']}'));
  }

  /// Vibrating reminder when this TM has poured for [truckReminderAfter]
  /// (pauses not counted) and is still not finished.
  Future<void> _scheduleReminder(Map<String, Object?> truck, {required Duration poured}) {
    final l = t(context);
    final left = truckReminderAfter - poured;
    return Notifications.scheduleTruckReminder(
      route: '/casting/log/${widget.uuid}',
      title: l.notifTruckLate('${truck['seq']}', truckReminderAfter.inMinutes, '${_pilePoint!['code']}'),
      body: l.notifTruckLateBody,
      at: DateTime.now().add(left),
    );
  }

  /// Pause the stopwatch of the truck being poured, with a reason.
  Future<void> _pauseTruck(Map<String, Object?> truck) async {
    final seq = toIntOrNull(truck['seq']) ?? 0;
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => _PauseReasonSheet(seq: seq),
    );
    if (reason == null || !mounted) return;
    final now = DateTime.now();
    final l = t(context);
    final reasonLabel = pauseReasonLabel(context, reason);
    // A pause is not pouring time: the reminder is set again on Lanjut.
    await Notifications.cancelTruckReminder();
    await Notifications.schedulePauseReminders(
      route: '/casting/log/${widget.uuid}',
      title: l.notifStillPaused(seq, '${_pilePoint!['code']}'),
      body: l.notifStillPausedBody,
      from: now,
    );
    if (!await _update((d) {
      final list = (d['pauses'] as List?) ?? <Object?>[];
      list.add(<String, Object?>{
        'uuid': newUuid(),
        'truckSeq': seq,
        'startAt': isoWithOffset(now),
        'endAt': null,
        'reason': reason,
        'note': null,
      });
      d['pauses'] = list;
    })) {
      return;
    }
    await Notifications.showPaused(
      route: '/casting/log/${widget.uuid}',
      title: l.notifPausedTitle(seq),
      body: l.notifPausedBody(reasonLabel),
      subText: _notifSubText,
      detail: _notifDetail(truck),
    );
    if (mounted) showSnack(context, l.pourPaused(reasonLabel), icon: Icons.pause_circle_outline);
  }

  /// Close the open pause of [seq] at [at], if there is one.
  void _closePause(Map<String, Object?> d, int seq, DateTime at) {
    for (final x in (d['pauses'] as List? ?? const [])) {
      final m = x as Map;
      if ('${m['truckSeq']}' == '$seq' && m['endAt'] == null) m['endAt'] = isoWithOffset(at);
    }
  }

  Future<void> _resumeTruck(Map<String, Object?> truck) async {
    final seq = toIntOrNull(truck['seq']) ?? 0;
    final now = DateTime.now();
    final l = t(context);
    if (!await _update((d) => _closePause(d, seq, now))) return;
    await Notifications.cancelPauseReminders();
    // The notification clock cannot pause: restart it from a start moved
    // forward by the paused time, so it shows pouring time only.
    final poured = pouringTime(truck, _pauses, now) ?? Duration.zero;
    await Notifications.showStopwatch(
      route: '/casting/log/${widget.uuid}',
      title: l.notifPouring('$seq'),
      body: l.notifTapToOpen(_decimal(truck['volumeM3'])),
      start: now.subtract(poured),
      subText: _notifSubText,
      detail: _notifDetail(truck),
      progress: _notifProgress,
    );
    await _scheduleReminder(truck, poured: poured);
    if (mounted) showSnack(context, l.pourResumed(seq));
  }

  Future<void> _finishTruck(Map<String, Object?> truck) async {
    final end = DateTime.now();
    final l = t(context);
    final finishedSeq = toIntOrNull(truck['seq']) ?? 0;
    final saved = await _update((d) {
      _closePause(d, finishedSeq, end);
      for (final x in (d['trucks'] as List)) {
        final m = x as Map;
        if (m['uuid'] == truck['uuid']) m['endAt'] = isoWithOffset(end);
      }
    });
    if (!saved) return;
    await Notifications.clearStopwatch();
    await Notifications.cancelTruckReminder();
    await Notifications.cancelPauseReminders();
    // Waiting too long for the next truck risks a cold joint in the pile.
    await Notifications.scheduleIdleReminders(
      route: '/casting/log/${widget.uuid}',
      title: l.notifNoNextTruck('${_pilePoint!['code']}'),
      body: l.notifNoNextTruckBody,
      from: end,
    );
    if (!mounted) return;
    showSnack(context, l.truckFinished(finishedSeq));
    if (!await _askSoundingAfter(truck)) return;
    // Urutannya sengaja: sounding dulu (semua angka berdiri di atasnya),
    // baru periksa apakah betonnya masuk akal, baru tremie.
    if (!mounted) return;
    await _checkOveruseAfter(finishedSeq);
    if (!mounted) return;
    await _askPullTremie(finishedSeq);
  }

  /// Beton jauh di atas teoritis sesudah sounding.
  ///
  /// Dulu ini cuma banner yang mudah dilewati, dan Oktober 2026 terbukti:
  /// sebuah titik tercatat overbreak 70% tanpa seorang pun berhenti. Sebab
  /// yang paling sering BUKAN lubang membesar, melainkan satu TM yang
  /// dibagi dua lubang lalu diketik penuh di dua log — jadi itu yang
  /// ditawarkan lebih dulu.
  Future<void> _checkOveruseAfter(int seq) async {
    final k = _castingState;
    final over = k.overuseSoFarPercent(seq);
    if (over == null || over <= volumeLoudPercent) return;
    // DITANYA SEKALI SAJA per titik. Di tanah yang jelek setiap TM lewat
    // ambang ini, dan dialog yang muncul berulang kali akan ditekan tanpa
    // dibaca — persis kebiasaan yang membuat pertanyaan ini perlu ada.
    //
    // Penandanya dibaca dari catatan log, bukan dari memori layar: ia harus
    // tetap berlaku sesudah layar ditutup dan di HP mana pun log ini
    // dilanjutkan lewat Oper.
    if ('${_doc!['note'] ?? ''}'.contains(t(context).overbreakCheckedTag)) return;
    final truck = _trucks.where((x) => (toIntOrNull(x['seq']) ?? 0) == seq).firstOrNull;
    if (truck == null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) {
        final w = c.colors;
        return AlertDialog(
          icon: Icon(Icons.trending_up, size: 32, color: w.badFg),
          title: Text(t(c).overuseAfterTitle, textAlign: TextAlign.center),
          content: Text(t(c).overuseAfterBody(seq, over.toStringAsFixed(0)),
              style: TextStyle(color: w.ink, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'nanti'), child: Text(t(c).later)),
            TextButton(onPressed: () => Navigator.pop(c, 'lubang'), child: Text(t(c).holeReallyWider)),
            FilledButton(onPressed: () => Navigator.pop(c, 'betulkan'), child: Text(t(c).fixTruckVolume)),
          ],
        );
      },
    );
    if (choice == null || choice == 'nanti' || !mounted) return;
    if (choice == 'betulkan') {
      await _editTruck(truck);
      return;
    }
    final tag = t(context).overbreakCheckedTag;
    await _update((d) => d['note'] = _withNote(
          d['note'],
          '${t(context).widerHoleNote(seq, over.toStringAsFixed(0))} $tag',
        ));
  }

  /// Sesudah TM selesai: tawarkan cabut tremie lewat DIALOG, bukan banner.
  ///
  /// Banner saran sudah ada di layar, tetapi saat TM baru beres mandor
  /// sedang menatap HP — itu satu-satunya saat dia pasti membacanya. Yang
  /// ditanya cuma "sudah dicabut atau belum"; mencentangnya di sini sama
  /// persis dengan mencentang di daftar tremie.
  Future<void> _askPullTremie(int seq) async {
    final k = _castingState;
    final embedment = k.embedmentAfter(seq);
    const limits = EmbedmentLimits();
    final suggestion = chooseSegmentsToRemove(
      [for (final s in k.installedAfter(seq)) Segment(key: s.uuid, lengthM: s.lengthM)],
      embedment,
      limits,
    );
    if (suggestion.isEmpty) return;
    final position = {for (final s in k.segments) s.uuid: s.position};
    final which = suggestion.map((s) => '#${position[s.key]} (${_decimal(s.lengthM)} m)').join(', ');
    final after = embedment - suggestion.fold(0.0, (a, s) => a + s.lengthM);
    final pulled = await showDialog<bool>(
      context: context,
      builder: (c) {
        final w = c.colors;
        return AlertDialog(
          icon: Icon(Icons.north, size: 32, color: w.brand),
          title: Text(t(c).pullNowTitle, textAlign: TextAlign.center),
          content: Text(
            t(c).pullNowBody(seq, formatMeters(embedment), which, formatMeters(after)),
            style: TextStyle(color: w.ink, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).notYetPull)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).pulledAlready)),
          ],
        );
      },
    );
    if (pulled != true) return;
    for (final s in suggestion) {
      await _toggleRemoved(s.key, seq);
    }
  }

  /// The sounding after a truck is REQUIRED: every number after it (actual
  /// rise, overbreak, embedment, cut suggestion) stands on it. Asked when the
  /// truck finishes; if skipped, asked again before the next truck and
  /// before finishing the casting. Returns false when still not given.
  Future<bool> _askSoundingAfter(Map<String, Object?> truck) async {
    final k = _castingState;
    final seq = toIntOrNull(truck['seq']) ?? 0;
    final before = toDoubleOrNull(truck['concreteDepthBeforeM']) ?? k.concreteAfter(seq - 1).depthM;
    // DIULANG SAMPAI ANGKANYA MASUK AKAL, bukan ditanya sekali lalu
    // diterima apa adanya: yang menekan "Ukur ulang" harus kembali ke
    // kolom yang sama, bukan kehilangan seluruh isiannya.
    var awal = toDoubleOrNull(truck['concreteDepthAfterM']);
    while (true) {
      // Putaran kedua dan seterusnya datang SESUDAH dialog — layarnya bisa
      // sudah ditutup orangnya di antara keduanya, dan `context` yang
      // dipakai di bawah tidak lagi menempel ke pohon widget mana pun.
      if (!mounted) return false;
      final v = await _askNumber(
        title: t(context).soundingAfter('$seq'),
        label: t(context).concreteDepthField,
        icon: Icons.local_shipping_outlined,
        suffix: 'm',
        maxValue: 200,
        initial: awal,
        question: t(context).soundingQuestion,
        diagram: const SoundingDiagram(),
        hint: t(context).soundingHint(formatMeters(k.concreteAfter(seq).depthM)),
        validate: (v) => soundingProblem(v, before: before, bottom: k.geometry.bottomDepthM),
      );
      final value = v?.$1;
      if (value == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t(context).soundingMissing(seq))),
                ],
              ),
            ),
          );
        }
        return false;
      }
      if (!await _rasioMasukAkal(truck, seq: seq, before: before, after: value)) {
        awal = value;
        continue;
      }
      // The sounding is the gate before the next TM and before "Selesai cor":
      // report whether it was really stored, not just that it was typed.
      return _updateTruck('${truck['uuid']}', (t) => t['concreteDepthAfterM'] = decimalText(value));
    }
  }

  /// Rasio yang MELOMPAT dari pola titik ini ditanyakan dulu, tidak
  /// langsung disimpan.
  ///
  /// Kejadian nyata, 27 Okt 2026: satu titik berjalan 1,04 · 1,04 · 1,05
  /// lalu tiba-tiba 0,50 — dan yang 0,50 itu salah ketik sounding. Tanpa
  /// penjaga ini, angkanya masuk tanpa sepatah kata pun dan baru
  /// ketahuan kalau ada yang membaca rekapnya baris per baris.
  ///
  /// MEMPERINGATKAN, BUKAN MENOLAK. Lubang memang bisa menyempit
  /// (necking), dan menolak angka yang benar hanya mengajari orang
  /// mengetik angka yang salah supaya diterima. Yang ditahan hanya
  /// kecepatannya: angkanya diperlihatkan di samping pola titiknya
  /// sendiri, lalu orangnya memilih.
  ///
  /// Kembalian: true bila boleh disimpan.
  Future<bool> _rasioMasukAkal(
    Map<String, Object?> truck, {
    required int seq,
    required double before,
    required double after,
  }) async {
    final k = _castingState;
    final ratio = overbreakRatio(
      diameterMm: k.geometry.diameterMm,
      volumeM3: toDoubleOrNull(truck['volumeM3']) ?? 0,
      depthBeforeM: before,
      depthAfterM: after,
    );
    if (ratio == null) return true;
    final ganjil = overbreakOddity(ratio: ratio, sebelumnya: k.ratiosBefore(seq));
    if (ganjil == null) return true;
    // Layarnya sudah ditutup: tidak ada tempat untuk bertanya, dan
    // angkanya TETAP DISIMPAN. Membuangnya lebih buruk — sounding sesudah
    // adalah gerbang sebelum TM berikutnya, jadi yang hilang memaksa
    // orangnya mengukur ulang sesuatu yang sudah diukur. Yang hilang di
    // sini hanya pertanyaannya, bukan datanya.
    if (!mounted) return true;

    final pola = ganjil.sebelumnya.map(_persenLebih).join(' · ');
    final jawab = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, size: 32, color: c.colors.warnFg),
        title: Text(t(c).ratioOddTitle, textAlign: TextAlign.center),
        content: Text(
          ganjil.pembanding == null
              ? t(c).ratioOddAlone(_persenLebih(ratio))
              : t(c).ratioOddBody(_persenLebih(ratio), pola),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).saveAnyway)),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).remeasure)),
        ],
      ),
    );
    // Dialog ditutup lewat tombol kembali = belum memutuskan apa pun, dan
    // yang belum diputuskan tidak boleh berarti "simpan saja".
    return jawab ?? false;
  }

  /// The last finished truck still waiting for its sounding, if any.
  Map<String, Object?>? get _unsoundedTruck {
    final t = _lastTruck;
    return t != null && t['endAt'] != null && t['concreteDepthAfterM'] == null ? t : null;
  }

  Future<void> _editTime(Map<String, Object?> truck, {required bool start}) async {
    final key = start ? 'startAt' : 'endAt';
    final initial = DateTime.tryParse('${truck[key]}')?.toLocal() ?? DateTime.now();
    final fresh = await showTimeWheel(
      context,
      initial: initial,
      title: start ? t(context).truckStartTime('${truck['seq']}') : t(context).truckEndTime('${truck['seq']}'),
    );
    if (fresh == null) return;
    await _updateTruck('${truck['uuid']}', (t) {
      t[key] = isoWithOffset(fresh);
      t[start ? 'startEdited' : 'endEdited'] = true;
    });
  }

  Future<void> _editSounding(Map<String, Object?> truck, {required bool after}) async {
    final key = after ? 'concreteDepthAfterM' : 'concreteDepthBeforeM';
    final v = await _askNumber(
      title: after ? t(context).soundingAfter('${truck['seq']}') : t(context).soundingBefore('${truck['seq']}'),
      label: t(context).concreteDepthField,
      icon: Icons.local_shipping_outlined,
      suffix: 'm',
      maxValue: 200,
      initial: toDoubleOrNull(truck[key]),
      question: t(context).soundingQuestion,
      diagram: const SoundingDiagram(),
      // Before is optional; after is required and can only be corrected.
      allowEmpty: !after,
      validate: after
          ? (v) => soundingProblem(
                v,
                before: toDoubleOrNull(truck['concreteDepthBeforeM']) ??
                    _castingState.concreteAfter((toIntOrNull(truck['seq']) ?? 1) - 1).depthM,
                bottom: _castingState.geometry.bottomDepthM,
              )
          : null,
    );
    if (v == null) return; // cancelled
    final value = v.$1;
    // Pembetulan lewat ketukan baris melewati gerbang yang sama dengan
    // pengisian pertama. Kalau tidak, satu jalur menjaga dan satu jalur
    // tidak — dan yang salah ketik akan lewat dari jalur yang tidak.
    if (after && value != null) {
      final seqIni = toIntOrNull(truck['seq']) ?? 1;
      final sebelum = toDoubleOrNull(truck['concreteDepthBeforeM']) ??
          _castingState.concreteAfter(seqIni - 1).depthM;
      if (!await _rasioMasukAkal(truck, seq: seqIni, before: sebelum, after: value)) return;
    }
    await _updateTruck('${truck['uuid']}', (t) => t[key] = value == null ? null : decimalText(value));
    if (mounted) {
      showSnack(
        context,
        value == null
            ? t(context).soundingCleared('${truck['seq']}')
            : t(context).soundingSaved('${truck['seq']}', formatMeters(value)),
      );
    }
  }

  /// Data cor — mutu beton, kedalaman tremie, catatan.
  ///
  /// PEMASOK SUDAH TIDAK DI SINI.
  ///
  ///     "supplier per titik jangan pernah ada lagi deh bang"
  ///
  /// Satu titik dulu menyimpan pemasoknya di dua tempat: satu di kepala log
  /// ini, satu lagi di tiap TM. Keduanya berselisih tanpa satu pun galat —
  /// 26 Okt 2026 seluruh TM datang dari Adhimix sementara kepalanya menyebut
  /// Jayamix — dan yang membaca layar tidak punya cara tahu mana yang benar.
  ///
  /// Kepalanya kini selalu kosong di server. Kendalinya dicabut dari sini
  /// juga, sebab kendali yang masih dapat diketuk dan diubah padahal
  /// nilainya tidak disimpan ke mana pun adalah kebohongan yang lebih buruk
  /// daripada tidak ada kendali sama sekali: orangnya mengira sudah
  /// mencatat.
  Future<void> _editHeader() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _HeaderSheet(
        grade: toDoubleOrNull(_doc!['concreteGrade']),
        defaultGrade: toDoubleOrNull(_pilePoint!['concreteGrade']) ?? toDoubleOrNull(_project?['defaultConcreteGrade']),
        bottomDepthM: _castingState.geometry.bottomDepthM,
        tremieDepthStartM: toDoubleOrNull(_doc!['tremieDepthStartM']),
        note: _doc!['note']?.toString(),
      ),
    );
    if (result == null) return;
    if (!await _update((d) => d.addAll(result))) return;
    if (mounted) showSnack(context, t(context).castDataSaved);
  }

  /// Dua pertanyaan sebelum TM pertama, satu layar satu pertanyaan.
  ///
  /// Bukan `_editHeader`: lembar Data cor memuat enam isian sekaligus dan
  /// meminta kedalaman yang harus dihitung sendiri. Di sini yang ditanya
  /// hanya yang BISA DILIHAT — berapa meter pipa menyembul — dan
  /// kedalamannya diturunkan aplikasi. Data cor tetap ada untuk
  /// membetulkan apa pun sesudahnya.
  Future<void> _mulaiCor() async {
    final k = _castingState;
    final hasil = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _PourStartSheet(
        bottomDepthM: k.geometry.bottomDepthM,
        // Panjang SEBELUM TM pertama: belum ada satu segmen pun yang
        // dicabut, jadi ini seluruh rangkaian yang turun ke lubang.
        tremieLengthM: k.installedLengthAfter(0),
        grade: toDoubleOrNull(_doc!['concreteGrade']),
        defaultGrade: toDoubleOrNull(_pilePoint!['concreteGrade']) ??
            toDoubleOrNull(_project?['defaultConcreteGrade']),
      ),
    );
    if (hasil == null) return;
    if (!await _update((d) => d.addAll(hasil))) return;
    if (mounted) showSnack(context, t(context).castDataSaved);
  }

  /// Mutu beton belum terisi — log cor tidak boleh ditutup.
  bool get _mutuKosong => toDoubleOrNull(_doc?['concreteGrade']) == null;

  /// Kedalaman ujung tremie belum diukur, DAN belum ada satu TM pun.
  ///
  /// SATU-SATUNYA SAAT ANGKA INI MASIH ADA ADALAH SEKARANG.
  ///
  /// Dulu ia ditahan di tombol "Selesai cor" saja. Pada SP.B58 (27 Okt
  /// 2026) akibatnya terlihat: pengecoran selesai jam 16:33, tremie sudah
  /// tinggal 3,3 m, lalu tombol Selesai menolak dan meminta kedalaman
  /// ujung tremie SAAT MULAI — angka yang tiga jam sebelumnya masih bisa
  /// diukur dan saat itu sudah tidak ada lagi di dunia. Meteran tidak
  /// dapat diturunkan ke masa lalu; yang tersisa hanya menebak, atau
  /// mencatat asumsi aplikasi sebagai hasil ukur.
  ///
  /// Bedanya dengan mutu beton, yang ditahan di tombol Selesai dan memang
  /// pantas di sana: mutu beton masih terbaca di surat jalan sampai kapan
  /// pun. Yang ini tidak. Karena itu penahannya dipindahkan ke SEBELUM TM
  /// pertama — saat tremienya sudah tersusun dan lubangnya masih kosong.
  ///
  /// Hanya berlaku selama belum ada TM: sesudah itu saat mulainya memang
  /// sudah lewat, dan menahan di sana hanya mengulang kesalahan yang sama
  /// di tempat yang berbeda. Log yang sudah telanjur berjalan tetap
  /// dijaga penahan lama di tombol Selesai.
  bool get _ukurTremieDulu =>
      _trucks.isEmpty && toDoubleOrNull(_doc?['tremieDepthStartM']) == null;

  /// TM dengan nomor terkecil — yang sounding sebelumnya dicari.
  Map<String, Object?>? get _tmPertama => _trucks.isEmpty
      ? null
      : _trucks.reduce(
          (a, b) => (toIntOrNull(a['seq']) ?? 0) <= (toIntOrNull(b['seq']) ?? 0) ? a : b,
        );

  /// Apa saja yang masih kurang sebelum catatan cor boleh ditutup.
  ///
  /// SATU DAFTAR, SATU TEMPAT. Sebelumnya ketiganya berupa tiga penjagaan
  /// berturut-turut di `_finishCasting`, masing-masing menampilkan snack
  /// lalu pulang — jadi yang kurang tiga hal menekan Selesai tiga kali dan
  /// diberi tahu satu per satu, tanpa pernah melihat berapa sisanya.
  List<_Kurang> get _kurangUntukSelesai => [
        // Yang hanya dapat diukur di lokasi lebih dulu: kalau orangnya
        // menyerah di tengah, yang sempat terisi adalah yang paling tidak
        // dapat diisi ulang nanti.
        if (toDoubleOrNull(_doc?['tremieDepthStartM']) == null) _Kurang.tremie,
        if (_mutuKosong) _Kurang.mutu,
        if (_tmPertama != null &&
            toDoubleOrNull(_tmPertama!['concreteDepthBeforeM']) == null)
          _Kurang.soundingAwal,
      ];

  /// Tanyakan yang kurang SEKARANG, di tempat orangnya berdiri.
  ///
  /// DIMINTA DANIEL, 28 Okt 2026: "langsung tampilkan kartu untuk isi itu
  /// boleh ga bang? jadi orang ga bingung dan harus cari cari lagi".
  ///
  /// Sebelumnya tiap penghalang hanya menampilkan satu kalimat lalu
  /// menutup diri — "buka Data cor dan ukur dulu". Kalimat yang menyuruh
  /// orang membuka layar lain adalah kalimat yang dilewati, dan yang
  /// membacanya di samping rig sambil menunggu TM berikutnya melewatinya
  /// hampir pasti.
  ///
  /// Server memang menolak log yang kurang (`MUTU_KOSONG` dan
  /// kembarannya), tetapi penolakan itu datang saat sinkron — bisa
  /// berjam-jam sesudahnya, saat QS sudah pulang dan catatannya
  /// menggantung ditolak tanpa ada yang tahu.
  ///
  /// Kembalian: true bila sekarang sudah lengkap.
  Future<bool> _lengkapiDulu() async {
    final kurang = _kurangUntukSelesai;
    if (kurang.isEmpty) return true;
    final k = _castingState;
    final hasil = await showModalBottomSheet<_LengkapiHasil>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _LengkapiSheet(
        kurang: kurang,
        bottomDepthM: k.geometry.bottomDepthM,
        // Panjang SELURUH rangkaian, termasuk pipa yang sudah dicabut:
        // yang ditanya kembali ke keadaan SEBELUM TM pertama.
        tremieLengthM: k.installedLengthAfter(0),
        grade: toDoubleOrNull(_doc!['concreteGrade']),
        defaultGrade: toDoubleOrNull(_pilePoint!['concreteGrade']) ??
            toDoubleOrNull(_project?['defaultConcreteGrade']),
      ),
    );
    if (hasil == null) return false;
    if (hasil.doc.isNotEmpty && !await _update((d) => d.addAll(hasil.doc))) {
      return false;
    }
    final awal = hasil.soundingAwal;
    final tm = _tmPertama;
    if (awal != null && tm != null) {
      final ok = await _updateTruck(
        '${tm['uuid']}',
        (t) => t['concreteDepthBeforeM'] = decimalText(awal),
      );
      if (!ok) return false;
    }
    // Diperiksa ULANG dari keadaan terbaru, bukan dianggap beres karena
    // lembarnya ditutup: penyimpanan dapat gagal diam-diam, dan menutup
    // catatan atas dasar isian yang tidak tersimpan persis kesalahan yang
    // hendak dicegah penjagaan ini.
    return _kurangUntukSelesai.isEmpty;
  }

  Future<void> _finishCasting() async {
    final unsounded = _unsoundedTruck;
    if (unsounded != null && !await _askSoundingAfter(unsounded)) return;

    if (!await _lengkapiDulu()) return;
    if (!mounted) return;

    final k = _castingState;
    final last = k.lastSeq;
    final level = k.concreteAfter(last);
    // The other way round from adding a truck: finishing while the concrete
    // is still below cut-off leaves a short pile.
    final short = !k.reachedCutOffAfter(last);
    final missing = level.depthM - k.geometry.cutOffDepthM;
    if (!mounted) return;
    final result = await showDialog<_FinishResult>(
      context: context,
      builder: (_) => _FinishDialog(
        code: '${_pilePoint!['code']}',
        short: short,
        missingM: missing,
        levelDepthM: level.depthM,
        cutOffDepthM: k.geometry.cutOffDepthM,
        measured: level.measured,
        pouredM3: k.totalVolumeM3,
        theoreticalM3: k.geometry.actualTheoreticalVolumeM3 ?? k.geometry.plannedTheoreticalVolumeM3,
        areaM2: k.geometry.areaM2,
        averageTruckM3: k.trucks.isEmpty ? null : k.totalVolumeM3 / k.trucks.length,
      ),
    );
    if (result == null) return;
    // Save FIRST: the stopwatch and the reminders belong to a pour that is
    // still running, so they are only silenced once it really is finished.
    if (!await _update((d) {
      d['status'] = 'selesai';
      // The office must be able to see WHY a pile was closed short, so the
      // reason goes into the note the server already carries.
      if (result.note != null) d['note'] = _withNote(d['note'], result.note!);
    })) {
      return;
    }
    await Notifications.clearStopwatch();
    await Notifications.cancelTruckReminder();
    await Notifications.cancelPauseReminders();
    await Notifications.cancelIdleReminders();
    // Read it BACK before saying it is finished: the cleaning dialog and the
    // snackbar are the only proof the foreman gets, and they must never appear
    // over a log that is still running.
    if (!await _storedStatusIs('selesai')) {
      if (mounted) {
        showSnack(context, t(context).finishNotStored, icon: Icons.error_outline);
      }
      return;
    }
    if (!mounted) return;
    await _remindCleaning();
    if (mounted) showSnack(context, t(context).castFinished('${_pilePoint!['code']}'));
  }

  Future<void> _reopenCasting() async {
    // Sama seperti pada log bor: satu ketukan pada tombol di dalam banner
    // "Cor selesai" membuka kembali seluruh lognya tanpa satu pun
    // pertanyaan. Volume beton yang sudah dilaporkan ke kantor termasuk di
    // dalamnya.
    if (!await askConfirm(
      context,
      icon: Icons.lock_open_outlined,
      title: t(context).castReopenConfirmTitle,
      body: t(context).castReopenConfirmBody,
      confirmLabel: t(context).reopen,
    )) {
      return;
    }
    if (!mounted) return;
    if (!await _update((d) => d['status'] = 'berjalan')) return;
    if (mounted) showSnack(context, t(context).castReopened, icon: Icons.lock_open_outlined);
  }

  /// Add [line] to an existing note without losing what is already there.
  ///
  /// `DataCor.note` is capped at 500 characters on the server: a longer note
  /// makes the whole item invalid, so it is trimmed here rather than rejected
  /// after a day without signal.
  static String _withNote(Object? existing, String line) {
    final was = existing?.toString().trim() ?? '';
    final merged = was.isEmpty ? line : '$was\n$line';
    return merged.length <= 500 ? merged : merged.substring(0, 500);
  }

  /// What is really on disk for this document — the screen's own `_doc` is
  /// only a copy in memory.
  Future<bool> _storedStatusIs(String status) async {
    final row = await ref.read(dbProvider).getDocument(widget.uuid);
    if (row == null) return false;
    return (jsonDecode(row.body) as Map)['status'] == status;
  }

  /// After the last truck: wash the tremie and hopper before the next pour.
  /// Concrete left to set inside a pipe or a joint blocks the next casting.
  Future<void> _remindCleaning() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) {
          final w = c.colors;
          Widget step(IconData icon, String text) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: w.brand),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: TextStyle(color: w.ink, height: 1.4))),
                  ],
                ),
              );
          return AlertDialog(
            icon: Icon(Icons.cleaning_services_outlined, size: 32, color: w.brand),
            title: Text(t(c).cleanTremieTitle, textAlign: TextAlign.center),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TerraBanner(
                    kind: BannerKind.warning,
                    title: t(c).beforeNextUse,
                    body: t(c).cleanWhy,
                  ),
                  step(Icons.water_drop_outlined, t(c).cleanStep1),
                  step(Icons.link, t(c).cleanStep2),
                  step(Icons.schedule, t(c).cleanStep3),
                  step(Icons.inventory_2_outlined, t(c).cleanStep4),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c).cleanedOk)),
            ],
          );
        },
      );

  /// Null = cancelled. `(null,)` = cleared (if [allowEmpty]).
  Future<(double?,)?> _askNumber({
    required String title,
    required String label,
    required IconData icon,
    String? suffix,
    required double maxValue,
    double? initial,
    String? question,
    Widget? diagram,
    String? hint,
    bool allowEmpty = false,
    String? Function(double value)? validate,
  }) =>
      showNumberDialog(
        context,
        title: title,
        label: label,
        icon: icon,
        suffix: suffix,
        maxValue: maxValue,
        initial: initial,
        question: question,
        diagram: diagram,
        hint: hint,
        allowEmpty: allowEmpty,
        validate: validate,
      );

  // -------------------------------------------------------------------------
  // Display
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: Text(t(context).castLogTitle)), body: ErrorState(title: _error!));
    }
    if (_doc == null) return const Scaffold(body: LoadingState());

    final live = ref.watch(_liveDocProvider(widget.uuid)).value;
    if (live != null) _row = live;

    final w = context.colors;
    final k = _castingState;
    final g = _geometry;
    final lastTruck = _lastTruck;
    final running = _runningTruck;
    final seq = k.lastSeq;

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context).castOf('${_pilePoint!['code']}')),
        actions: [
          if (_row != null && !_finished && !_readOnly)
            IconButton(
              tooltip: t(context).handOverToMate,
              icon: const Icon(Icons.swap_horiz),
              onPressed: () =>
                  offerHandover(context, ref, entity: 'casting', uuid: widget.uuid, pointCode: '${_pilePoint!['code']}'),
            ),
          if (_row != null) Padding(padding: const EdgeInsets.only(right: 12), child: StatusBadge.sendStatus(context, _row!.sendStatus)),
        ],
      ),
      body: ListView(
        // The action buttons live in bottomNavigationBar, which the body already
        // ends above: no extra room needed under the last card.
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 8),
        children: [
          if (_peminta != null)
            TerraBanner(
              kind: BannerKind.warning,
              icon: Icons.pan_tool_alt_outlined,
              title: t(context).handoverRequestTitle(_peminta!),
              body: t(context).handoverRequestPrompt(_peminta!, '${_pilePoint!['code']}'),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => _jawabOper(false), child: Text(t(context).reject)),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: () => _jawabOper(true), child: Text(t(context).approve)),
                ],
              ),
            ),
          if (_handedAway)
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.swap_horiz,
              title: t(context).handedOverTo(_holderName ?? t(context).colleague),
              body: t(context).handedOverBody(_holderName ?? t(context).colleague),
            ),
          if (_row?.sendStatus == 'rejected' && !_handedAway)
            TerraBanner(kind: BannerKind.danger, title: t(context).rejectedByServer, body: reasonText(context, _row!.reason, _row!.detail)),
          if (_locked)
            TerraBanner(
              kind: BannerKind.ok,
              title: t(context).reviewedByOffice,
              body: [
                if (_row!.serverNote != null) t(context).officeNote('${_row!.serverNote}'),
                t(context).cannotChangeAnymore,
              ].join('\n'),
            ),
          if (_grade == null)
            TerraBanner(
              kind: BannerKind.warning,
              title: t(context).gradeMissingTitle,
              body: t(context).gradeMissingBody,
              action: TextButton(onPressed: _editHeader, child: Text(t(context).fill)),
            ),
          if (g.drilledDepthM == null)
            TerraBanner(
              kind: BannerKind.info,
              title: t(context).drillDepthUnmarked,
              body: t(context).drillDepthUnmarkedBody,
            ),

          _SummaryCard(geometry: g, castingState: k, grade: _grade, supplier: _suppliersFromTrucks, onEdit: _readOnly ? null : _editHeader),
          if (_row?.serverStatus != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: ReviewBadge(status: _row!.serverStatus!)),

          // --- live cross-section -------------------------------------------
          if (_tremie.isNotEmpty) _sectionView(k),
          ?_overuseBanner(k),

          // --- tremie -----------------------------------------------------
          _SectionTitle(t(context).tremieSection, t(context).tremieSectionBody(formatMeters(k.bottomGapM))),
          _TremieCard(
            castingState: k,
            currentSeq: seq,
            canEditLayout: !_readOnly && _trucks.isEmpty,
            canRemove: !_readOnly && seq > 0,
            onAdd: _addSegment,
            onAddBottom: _addBottom,
            onCustom: _customSegment,
            onRemoveTop: _removeTopSegment,
            onToggleRemoved: (uuid, seq) => _toggleRemoved(uuid, seq, tanya: true),
          ),

          // --- recommendation -----------------------------------------------
          if (seq > 0 && !_finished) _suggestionCard(k, seq),

          // --- TM ---------------------------------------------------------
          _SectionTitle(t(context).trucksSection, t(context).trucksSectionBody(_trucks.length, _decimal(k.totalVolumeM3))),
          for (final truck in _trucks..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0)))
            _TruckCard(
              truck: truck,
              castingState: k,
              locked: _readOnly,
              onEdit: () => _editTruck(truck),
              onStart: () => _startTruck(truck),
              onFinish: () => _finishTruck(truck),
              onEditStart: () => _editTime(truck, start: true),
              onEditEnd: () => _editTime(truck, start: false),
              onSoundingBefore: () => _editSounding(truck, after: false),
              onSoundingAfter: () => _editSounding(truck, after: true),
              pauses: pausesOf(_pauses, toIntOrNull(truck['seq']) ?? 0),
            ),
          if (_trucks.isEmpty)
            ListCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: w.brandSoft, shape: BoxShape.circle),
                    child: Icon(Icons.local_shipping_outlined, color: w.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(context).noTrucksYet, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                        const SizedBox(height: 2),
                        Text(
                          _readOnly
                              ? t(context).noTrucksReadOnly
                              : _tremie.isEmpty
                                  ? t(context).noTrucksTremieFirst
                                  : t(context).noTrucksTapArrived,
                          style: TextStyle(color: w.muted, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _readOnly
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 8, Dimens.pagePadding, 12),
                child: Row(
                  children: [
                    if (!_finished && running == null && _trucks.isNotEmpty)
                      Expanded(
                        // Tombol MATI, dan sebabnya tertulis DI TOMBOLNYA.
                        //
                        // Bukan dialog: dialog yang muncul tiap kali akan
                        // ditutup tanpa dibaca dalam sepekan, dan sesudah itu
                        // dialog mana pun — termasuk yang benar-benar genting
                        // — ikut tidak dibaca. Tombol mati tidak menuntut
                        // siapa pun membaca apa pun; ia hanya tidak bisa
                        // ditekan, dan alasannya ada tepat di tempat jari
                        // mendarat.
                        child: OutlinedButton(
                          onPressed: _mutuKosong ? null : _finishCasting,
                          child: Text(
                            _mutuKosong
                                ? t(context).finishNeedsGrade
                                : t(context).finishCasting,
                          ),
                        ),
                      ),
                    if (!_finished && running == null && _trucks.isNotEmpty) const SizedBox(width: 10),
                    if (!_finished && running != null) ...[
                      Expanded(
                        child: SizedBox(
                          height: Dimens.minTouch + 4,
                          child: openPause(_pauses, toIntOrNull(running['seq']) ?? 0) == null
                              ? OutlinedButton.icon(
                                  onPressed: () => _pauseTruck(running),
                                  icon: const Icon(Icons.pause),
                                  label: Text(t(context).pause),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _resumeTruck(running),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(t(context).resume),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (!_finished)
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: Dimens.minTouch + 4,
                          child: running != null
                              ? FilledButton.icon(
                                  onPressed: () => _finishTruck(running),
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: Text(t(context).finishTruck('${running['seq']}')),
                                )
                              : lastTruck != null && lastTruck['startAt'] == null
                                  ? FilledButton.icon(
                                      onPressed: () => _startTruck(lastTruck),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text(t(context).startTruck('${lastTruck['seq']}')),
                                    )
                                  // Labelnya sudah berganti jadi "Susun
                                  // tremie dulu", jadi yang kurang bukan APA
                                  // melainkan DI MANA — dan itu yang dijawab
                                  // kalau tombolnya tetap ditekan.
                                  : BlockedAction(
                                      reason: _tremie.isEmpty
                                          ? t(context).blockedNeedTremie
                                          : _ukurTremieDulu
                                              ? t(context).blockedNeedTremieDepth
                                              : null,
                                      icon: _tremie.isEmpty ? Icons.plumbing : Icons.straighten,
                                      // Ketukannya MEMBUKA pertanyaannya,
                                      // bukan menyuruh orang mencarinya
                                      // sendiri: isiannya ada di layar lain,
                                      // dan petunjuk arah di snack adalah hal
                                      // yang paling mudah dilewati.
                                      onTap: _tremie.isNotEmpty && _ukurTremieDulu
                                          ? () {
                                              _mulaiCor();
                                            }
                                          : null,
                                      child: FilledButton.icon(
                                        onPressed: _tremie.isEmpty || _ukurTremieDulu ? null : _newTruck,
                                        icon: const Icon(Icons.local_shipping_outlined),
                                        label: Text(_tremie.isEmpty
                                            ? t(context).tremieFirst
                                            : _ukurTremieDulu
                                                ? t(context).tremieDepthFirst
                                                : t(context).truckArrived(seq + 1)),
                                      ),
                                    ),
                        ),
                      ),
                    if (_finished)
                      Expanded(
                        child: TerraBanner(
                          kind: BannerKind.ok,
                          title: t(context).castDone,
                          body: _isNew ? null : t(context).savedAutoSend,
                          action: TextButton(onPressed: _reopenCasting, child: Text(t(context).reopen)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  /// The live cross-section, with the concrete level estimated while a
  /// truck pours from how long a truck usually takes on this pile.
  Widget _sectionView(CastingState k) {
    final running = _runningTruck;
    final seq = running == null ? null : toIntOrNull(running['seq']);
    return PileSectionView(
      snapshot: _snapshotNow(k),
      pouring: running != null,
      paused: seq != null && openPause(_pauses, seq) != null,
    );
  }

  /// The pile right now, with the concrete level estimated while a truck
  /// pours. Shared by the cross-section and the guard on removing tremie.
  PileSnapshot _snapshotNow(CastingState k) {
    final now = DateTime.now();
    final running = _runningTruck;
    final seq = running == null ? null : toIntOrNull(running['seq']);
    final finished = [
      for (final t in _trucks)
        if (t['endAt'] != null) pouringTime(t, _pauses, now),
    ].whereType<Duration>().where((d) => d.inSeconds > 60).toList();
    final typical = finished.isEmpty
        ? const Duration(minutes: 12)
        : Duration(seconds: finished.fold(0, (a, d) => a + d.inSeconds) ~/ finished.length);
    return pileSnapshot(
      k,
      pouringSeq: seq,
      poured: running == null ? Duration.zero : (pouringTime(running, _pauses, now) ?? Duration.zero),
      typicalPour: typical,
    );
  }

  /// Concrete used so far well over theory: the hole is probably wider.
  Widget? _overuseBanner(CastingState k) {
    final seq = k.trucks.where((t) => t.concreteAfterM != null).map((t) => t.seq).fold(0, math.max);
    final over = k.overuseSoFarPercent(seq);
    if (over == null || over < overuseWarnPercent) return null;
    final used = k.trucks.where((t) => t.seq <= seq).fold(0.0, (a, t) => a + t.volumeM3);
    final level = k.concreteAfter(seq).depthM;
    return TerraBanner(
      kind: BannerKind.warning,
      icon: Icons.trending_up,
      title: t(context).overuseTitle(over.toStringAsFixed(0)),
      body: t(context).overuseBody(formatMeters(level), _decimal(used),
          _decimal(k.geometry.areaM2 * (k.geometry.bottomDepthM - level))),
    );
  }

  /// Plan / cut suggestion for the latest TM.
  Widget _suggestionCard(CastingState k, int seq) {
    final truck = _lastTruck!;
    const limits = EmbedmentLimits();
    final installedSegments = [
      for (final s in k.installedAfter(seq)) Segment(key: s.uuid, lengthM: s.lengthM),
    ];

    if (truck['endAt'] == null) {
      // TM not finished: the plan is computed from the state BEFORE this TM.
      final before = k.concreteAfter(seq - 1).depthM;
      final r = planTruck(
        diameterMm: k.geometry.diameterMm,
        tremieBottomM: k.tremieBottomAfter(seq - 1),
        segments: [for (final s in k.installedAfter(seq - 1)) Segment(key: s.uuid, lengthM: s.lengthM)],
        concreteDepthM: toDoubleOrNull(truck['concreteDepthBeforeM']) ?? before,
        cutOffDepthM: k.geometry.cutOffDepthM,
        volumeM3: toDoubleOrNull(truck['volumeM3']) ?? 0,
        ratio: k.averageRatio,
        isFirstTruck: seq == 1,
        limits: limits,
      );
      final position = {for (final s in k.segments) s.uuid: s.position};
      return TerraBanner(
        kind: r.warnings.isEmpty ? BannerKind.info : BannerKind.warning,
        icon: Icons.tips_and_updates_outlined,
        title: r.cuts.isEmpty ? t(context).planNoPull(seq) : t(context).planTitle(seq),
        body: [
          for (final p in r.cuts)
            t(context).planCutLine(
              _decimal(p.afterM3),
              p.toRemove.map((s) => '#${position[s.key]} (${_decimal(s.lengthM)} m)').join(t(context).joinThen),
              _decimal(p.embedmentBeforeM),
              _decimal(p.embedmentAfterM),
            ),
          for (final p in r.warnings)
            p.kind == WarningKind.embedmentTooShort
                ? t(context).warnEmbedShort(_decimal(p.embedmentM))
                : t(context).warnNoSafePull(_decimal(p.afterM3)),
          t(context).planEnd(
            formatMeters(r.finalConcreteDepthM),
            formatMeters(r.finalEmbedmentM),
            r.cutOffReached ? t(context).cutOffReachedSuffix : '',
          ),
          if (k.averageRatio != 1.0) t(context).usingOverbreak(_decimal(k.averageRatio)),
        ].join('\n'),
      );
    }

    // TM finished: suggestion from the current embedment.
    final concreteAt = k.concreteAfter(seq);
    final embedment = k.embedmentAfter(seq);
    final suggestion = chooseSegmentsToRemove(installedSegments, embedment, limits);
    final position = {for (final s in k.segments) s.uuid: s.position};
    final kind = embedment < limits.minimumM
        ? BannerKind.danger
        : embedment > limits.maximumM
            ? BannerKind.warning
            : BannerKind.info;
    return TerraBanner(
      kind: kind,
      icon: Icons.tips_and_updates_outlined,
      title: t(context).embedTitle(formatMeters(embedment), concreteAt.measured ? '' : t(context).estimateSuffix),
      body: [
        if (!concreteAt.measured) t(context).notSoundedYet,
        if (suggestion.isEmpty)
          embedment < limits.minimumM ? t(context).dontPullUnderOne : t(context).noPullNeeded
        else
          t(context).pullSuggestion(
            suggestion.map((s) => '#${position[s.key]} (${_decimal(s.lengthM)} m)').join(', '),
            formatMeters(embedment - suggestion.fold(0.0, (a, s) => a + s.lengthM)),
          ),
      ].join('\n'),
      action: suggestion.isEmpty
          ? null
          : TextButton(
              onPressed: () async {
                for (final s in suggestion) {
                  await _toggleRemoved(s.key, seq);
                }
              },
              child: Text(t(context).tick),
            ),
    );
  }
}

final _liveDocProvider = StreamProvider.autoDispose.family<DocumentRow?, String>(
  (ref, uuid) => ref.watch(dbProvider).watchDocument(uuid),
);

String _decimal(Object? v, {int d = 2}) {
  final x = v is num ? v.toDouble() : toDoubleOrNull(v);
  if (x == null) return '–';
  var t = x.toStringAsFixed(d);
  if (t.contains('.')) t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
          Text(body, style: TextStyle(color: w.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.geometry, required this.castingState, required this.grade, required this.supplier, this.onEdit});

  final PileGeometry geometry;
  final CastingState castingState;
  final double? grade;
  final String? supplier;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final theoretical = geometry.actualTheoreticalVolumeM3 ?? geometry.plannedTheoreticalVolumeM3;
    final overuse = castingState.overusePercent;
    final seq = castingState.lastSeq;
    final concreteAt = castingState.concreteAfter(seq);
    Widget cell(String label, String value, {Color? colors}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: w.muted, fontSize: 12)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: colors ?? w.ink)),
            ],
          ),
        );
    return ListCard(
      onTap: onEdit,
      child: Column(
        children: [
          Row(children: [
            cell(t(context).fieldDiameter, 'D${geometry.diameterMm}'),
            cell(t(context).cellGrade, grade == null ? '–' : '${_decimal(grade, d: 1)} MPa', colors: grade == null ? w.warnFg : null),
            cell(t(context).cellSupplier, supplier ?? '–'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell(t(context).cellHoleBottom, formatMeters(geometry.bottomDepthM)),
            cell(t(context).cellCutOff, formatMeters(geometry.cutOffDepthM)),
            cell(t(context).cellConcreteLevel, '${formatMeters(concreteAt.depthM)}${concreteAt.measured || seq == 0 ? '' : '*'}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell(t(context).cellTheoretical, '${_decimal(theoretical)} m³'),
            cell(t(context).cellUsed, '${_decimal(castingState.totalVolumeM3)} m³'),
            cell(t(context).cellOveruse, overuse == null ? '–' : '${overuse >= 0 ? '+' : ''}${_decimal(overuse, d: 1)}%'),
          ]),
          if (seq > 0 && !concreteAt.measured) ...[
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text(t(context).estimatedFootnote, style: TextStyle(color: w.faint, fontSize: 12))),
          ],
        ],
      ),
    );
  }
}

class _TremieCard extends StatelessWidget {
  const _TremieCard({
    required this.castingState,
    required this.currentSeq,
    required this.canEditLayout,
    required this.canRemove,
    required this.onAdd,
    required this.onAddBottom,
    required this.onCustom,
    required this.onRemoveTop,
    required this.onToggleRemoved,
  });

  final CastingState castingState;
  final int currentSeq;
  final bool canEditLayout;
  final bool canRemove;
  final Future<void> Function(double) onAdd;
  final VoidCallback onAddBottom;
  final VoidCallback onCustom;
  final VoidCallback onRemoveTop;
  final Future<void> Function(String uuid, int? seq) onToggleRemoved;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final k = castingState;
    final total = k.segments.fold(0.0, (a, s) => a + s.lengthM);
    final requiredLength = k.geometry.bottomDepthM - k.bottomGapM;
    final installed = k.installedAfter(currentSeq);
    final bottom = installed.isEmpty ? null : installed.first.uuid;

    // Where each segment still in the hole hangs, depth from GS (negative =
    // above ground): stacked up from the tremie's lower end.
    final hangs = <String, ({double top, double bottom})>{};
    var lower = k.tremieBottomAfter(currentSeq);
    for (final s in installed) {
      hangs[s.uuid] = (top: lower - s.lengthM, bottom: lower);
      lower -= s.lengthM;
    }

    // Status and the add buttons sit ABOVE the list: each tap adds a row
    // below them, so the buttons stay under the thumb instead of moving
    // down the screen with every segment.
    final stickUp = k.tremieStickUpM;
    final (statusText, statusColor, statusIcon) = !canEditLayout
        ? (
            'Terpasang ${_decimal(k.installedLengthAfter(currentSeq))} m dari ${_decimal(total)} m · '
                'ujung bawah di ${formatMeters(k.tremieBottomAfter(currentSeq))}',
            w.muted,
            Icons.straighten,
          )
        : k.segments.isEmpty
            ? (t(context).tremieNeedFrom(formatMeters(requiredLength)), w.muted, Icons.straighten)
            : k.tremieTooLong
                ? (
                    t(context).tremieOverLong(formatMeters(stickUp), formatMeters(tremieStickUpMaxM)),
                    w.badFg,
                    Icons.error_outline,
                  )
                : k.tremieReachesBottom
                    ? (
                        t(context).tremieAtBottom(formatMeters(math.max(stickUp, 0))),
                        w.okFg,
                        Icons.check_circle_outline,
                      )
                    : (t(context).tremieShortBy(formatMeters(requiredLength - total)), w.warnFg, Icons.warning_amber_rounded);

    final progress = requiredLength <= 0 ? 0.0 : (total / requiredLength).clamp(0.0, 1.0);

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_decimal(total)} m',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: w.ink, height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(t(context).ofNeeded(formatMeters(requiredLength)), style: TextStyle(color: w.muted, fontSize: 13)),
              ),
            ],
          ),
          if (canEditLayout) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: w.line,
                color: statusColor == w.muted ? w.brand : statusColor,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13, height: 1.35)),
              ),
            ],
          ),
          if (canEditLayout && k.segments.isEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: Dimens.minTouch,
              child: FilledButton.tonalIcon(
                onPressed: onAddBottom,
                icon: const Icon(Icons.change_history),
                label: Text(t(context).fitBottomPiece),
              ),
            ),
          ],
          if (canEditLayout && k.segments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [1.0, 1.5, 2.0, 3.0])
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text('${_decimal(p)} m'),
                    // Greyed out when this piece would stand the tremie too
                    // high above GS; tapping it anyway explains why.
                    onPressed: () => onAdd(p),
                    backgroundColor: k.stickUpWith(p) > tremieStickUpMaxM + 0.005 ? w.line : null,
                  ),
                ActionChip(label: Text(t(context).other), onPressed: onCustom),
                ActionChip(avatar: const Icon(Icons.remove, size: 16), label: Text(t(context).removeTop), onPressed: onRemoveTop),
              ],
            ),
          ],
          if (k.segments.isNotEmpty) const Divider(height: 24),
          // Listed from the TOP, like the tremie in the hole drawn above.
          if (canRemove && k.segments.isNotEmpty)
            TerraBanner(
              kind: BannerKind.info,
              title: t(context).pullTremieTitle,
              body: t(context).pullTremieBody,
            ),
          for (final (i, s) in k.segments.reversed.indexed)
            Builder(builder: (context) {
              final at = hangs[s.uuid];
              final removed = s.removedAfterTruck != null;
              final canCheck = canRemove && !s.isBottom && s.uuid != bottom && (!removed || s.removedAfterTruck == currentSeq);
              final lowest = s.uuid == bottom;
              void toggle() => onToggleRemoved(s.uuid, removed ? null : currentSeq);
              return TremieSegmentTile(
                part: s.isBottom ? TremiePart.bottom : TremiePart.pipe,
                first: i == 0,
                last: i == k.segments.length - 1,
                removed: removed,
                lowest: lowest && !removed,
                number: s.position,
                title: s.isBottom ? t(context).tremieBottomOf(_decimal(s.lengthM)) : t(context).pipeOf(_decimal(s.lengthM)),
                subtitle: removed
                    ? t(context).pulledAfterTruck('${s.removedAfterTruck}')
                    : [
                        if (at != null) _hangText(context, at.top, at.bottom),
                        if (lowest) t(context).lowest,
                      ].join(' · '),
                onTap: canCheck ? toggle : null,
                trailing: !canCheck
                    ? null
                    : removed
                        ? TextButton.icon(onPressed: toggle, icon: const Icon(Icons.undo, size: 18), label: Text(t(context).cancel))
                        : OutlinedButton.icon(
                            onPressed: toggle,
                            icon: const Icon(Icons.north, size: 18),
                            label: Text(t(context).pull),
                          ),
              );
            }),
        ],
      ),
    );
  }
}

class _TruckCard extends StatelessWidget {
  const _TruckCard({
    required this.truck,
    required this.castingState,
    required this.locked,
    required this.onEdit,
    required this.onStart,
    required this.onFinish,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onSoundingBefore,
    required this.onSoundingAfter,
    required this.pauses,
  });

  final Map<String, Object?> truck;
  final CastingState castingState;
  final bool locked;
  final VoidCallback onEdit;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onEditStart;
  final VoidCallback onEditEnd;
  final VoidCallback onSoundingBefore;
  final VoidCallback onSoundingAfter;

  /// This truck's pauses, oldest first.
  final List<Map<String, Object?>> pauses;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final start = DateTime.tryParse('${truck['startAt']}');
    final end = DateTime.tryParse('${truck['endAt']}');
    final running = start != null && end == null;
    final now = DateTime.now();
    final seq = toIntOrNull(truck['seq']) ?? 0;
    // Pouring time only: the pauses are left out.
    final elapsed = pouringTime(truck, pauses, now);
    final paused = running && openPause(pauses, seq) != null;
    final pausedTotal = pausedTime(pauses, seq, end ?? now);
    final ratio = overbreakRatio(
      diameterMm: castingState.geometry.diameterMm,
      volumeM3: toDoubleOrNull(truck['volumeM3']) ?? 0,
      depthBeforeM: toDoubleOrNull(truck['concreteDepthBeforeM']) ?? castingState.concreteAfter(seq - 1).depthM,
      depthAfterM: toDoubleOrNull(truck['concreteDepthAfterM']),
    );

    // Tertanamnya ujung bawah tremie di beton segar, sebelum dan sesudah TM
    // ini. Ujung tremie SELAMA TM ini memakai cabutan sampai TM sebelumnya:
    // segmen yang dicabut setelah TM ini belum terangkat waktu betonnya
    // dituang, jadi memakainya akan melaporkan tertanam yang tidak pernah
    // ada.
    //
    // Dua angka, bukan satu. Yang sebelum menjawab "apakah ujungnya masih
    // cukup dalam waktu beton ini mulai masuk"; yang sesudah menjawab
    // "apakah sekarang sudah terlalu dalam sehingga perlu dicabut". Satu
    // angka saja menyembunyikan salah satu dari dua kegagalan yang berbeda.
    const batasTanam = EmbedmentLimits();
    final tremieBottom = castingState.tremieBottomAfter(seq - 1);
    final soundingSebelum = toDoubleOrNull(truck['concreteDepthBeforeM']);
    final soundingSesudah = toDoubleOrNull(truck['concreteDepthAfterM']);
    // Muka beton SEBELUM TM ini: soundingnya sendiri bila ada, kalau tidak
    // keadaan sesudah TM sebelumnya.
    //
    // QS menyounding sesudah menuang, bukan sebelum; memakai soundingnya
    // sendiri saja membuat baris ini kosong di hampir setiap TM. `concreteAfter`
    // memulangkan sounding TM sebelumnya bila ada, dan menaksir dari volume
    // bila tidak — taksiran itu DITANDAI "(perkiraan)", seperti di seluruh
    // layar ini. TM #1 tidak punya tertanam awal sama sekali: belum ada beton.
    final mukaSebelum = seq > 1 ? castingState.concreteAfter(seq - 1) : null;
    final tertanamAwal = soundingSebelum != null
        ? tremieBottom - soundingSebelum
        : (mukaSebelum == null ? null : tremieBottom - mukaSebelum.depthM);
    final awalPerkiraan = soundingSebelum == null && mukaSebelum != null && !mukaSebelum.measured;
    final tertanamAkhir = soundingSesudah == null ? null : tremieBottom - soundingSesudah;
    Color? warnaTanam(double? v) {
      if (v == null) return null;
      if (v < batasTanam.minimumM - 0.005) return w.badFg;
      if (v > batasTanam.maximumM + 0.005) return w.warnFg;
      return null;
    }

    Widget value(String label, String body, {VoidCallback? onTap, bool edited = false, Color? warna}) => InkWell(
          onTap: locked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(label, style: TextStyle(color: w.muted, fontSize: 13))),
                Text(body, style: TextStyle(fontWeight: FontWeight.w600, color: warna ?? w.ink)),
                if (edited) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.edit, size: 13, color: w.warnFg)),
                if (onTap != null && !locked) Icon(Icons.chevron_right, size: 16, color: w.faint),
              ],
            ),
          ),
        );

    return ListCard(
      edgeColor: running ? w.warnFg : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The header is the way in to correcting what was typed when
              // the TM arrived; the pencil says so without a second button.
              Expanded(
                child: InkWell(
                  onTap: locked ? null : onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(t(context).truckHeading(seq, _decimal(truck['volumeM3'])),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                        ),
                        if (!locked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.edit_outlined, size: 15, color: w.faint),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (elapsed != null && !running)
                Text(formatDuration(elapsed),
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w800,
                      color: w.muted,
                    )),
            ],
          ),
          if (running && elapsed != null) _PourClock(elapsed: elapsed, paused: paused),
          Text(
            [
              if (truck['truckNo'] != null) t(context).hullNo('${truck['truckNo']}'),
              if (truck['ticketNo'] != null) t(context).ticketNo('${truck['ticketNo']}'),
              if (truck['supplierName'] != null) '${truck['supplierName']}',
              if (truck['slumpCm'] != null) t(context).slumpOf(_decimal(truck['slumpCm'], d: 1)),
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          value(t(context).tremieFitted, '${_decimal(truck['tremieLengthM'])} m'),
          if (tertanamAwal != null)
            value(
              t(context).embedBeforeLabel,
              '${formatMeters(tertanamAwal)}${awalPerkiraan ? t(context).estimateSuffix : ''}',
              warna: warnaTanam(tertanamAwal),
            ),
          if (tertanamAkhir != null)
            value(t(context).embedAfterLabel, formatMeters(tertanamAkhir), warna: warnaTanam(tertanamAkhir)),
          value(t(context).start, start == null ? '–' : formatTime(start), onTap: start == null ? null : onEditStart, edited: truck['startEdited'] == true),
          value(t(context).finish, end == null ? '–' : formatTime(end), onTap: end == null ? null : onEditEnd, edited: truck['endEdited'] == true),
          if (pauses.isNotEmpty) ...[
            value(t(context).pause, t(context).pausesCount(pauses.length, formatDuration(pausedTotal))),
            for (final p in pauses)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  t(context).pauseLine(pauseReasonLabel(context, p['reason']), _clock(p['startAt']),
                      p['endAt'] == null ? t(context).now : _clock(p['endAt'])),
                  style: TextStyle(color: w.muted, fontSize: 13),
                ),
              ),
          ],
          value(t(context).soundingBeforeLabel, truck['concreteDepthBeforeM'] == null ? '–' : formatMeters(toDoubleOrNull(truck['concreteDepthBeforeM'])),
              onTap: onSoundingBefore),
          value(t(context).soundingAfterLabel, truck['concreteDepthAfterM'] == null ? '–' : formatMeters(toDoubleOrNull(truck['concreteDepthAfterM'])),
              onTap: end == null ? null : onSoundingAfter),
          if (end != null && truck['concreteDepthAfterM'] == null && !locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: w.badFg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t(context).soundingAfterRequired,
                        style: TextStyle(color: w.badFg, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
          if (ratio != null) value(t(context).overbreakRatio, _persenLebih(ratio)),
          if (truck['ticketPhotoUuid'] != null || truck['slumpPhotoUuid'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (truck['ticketPhotoUuid'] != null)
                    _CastingPhoto(uuid: '${truck['ticketPhotoUuid']}', label: t(context).deliveryNote),
                  if (truck['ticketPhotoUuid'] != null && truck['slumpPhotoUuid'] != null) const SizedBox(width: 8),
                  if (truck['slumpPhotoUuid'] != null)
                    _CastingPhoto(uuid: '${truck['slumpPhotoUuid']}', label: t(context).slumpTest),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tampilkan satu foto selayar penuh, bisa dicubit untuk diperbesar.
void _showPhotoFull(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(File(path)))),
  );
}

/// Satu foto TM di dalam lembar isian: tombol kamera sebelum ada foto, lalu
/// pratinjaunya begitu foto diambil.
///
/// Sebelum ini tombolnya hanya berubah jadi centang, sehingga tidak ada cara
/// melihat apa yang sebenarnya terpotret. Surat jalan yang blur atau kena
/// silau lampu baru ketahuan di kantor keesokan harinya, dan saat itu TM-nya
/// sudah pulang — tidak ada lagi yang bisa difoto ulang. Karena itu
/// pratinjaunya muncul di tempat, lengkap dengan tombol ulangi.
class _PhotoField extends ConsumerWidget {
  const _PhotoField({
    required this.uuid,
    required this.label,
    required this.emptyLabel,
    required this.icon,
    this.onTake,
  });

  final String? uuid;
  final String label;
  final String emptyLabel;

  final IconData icon;

  /// `null` = BACA SAJA.
  ///
  /// Dipakai foto slump sesudah pengambilannya dicabut (19 Okt 2026): 60 TM
  /// terlanjur punya fotonya, dan foto yang ada tetapi tidak dapat dibuka
  /// sama saja dengan hilang.
  final Future<void> Function()? onTake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final id = uuid;
    if (id == null) {
      return OutlinedButton.icon(onPressed: onTake, icon: Icon(icon), label: Text(emptyLabel));
    }
    final photo = ref.watch(_photoProvider(id)).value;
    // Berkasnya bisa tidak ada di HP INI: log yang dioper membawa nomor
    // fotonya, bukan gambarnya.
    final ada = photo != null && File(photo.path).existsSync();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: w.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Row(
        children: [
          if (ada)
            GestureDetector(
              onTap: () => _showPhotoFull(context, photo.path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(photo.path), height: 56, width: 56, fit: BoxFit.cover, cacheHeight: 168),
              ),
            )
          else
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(color: w.surface, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.image_not_supported_outlined, color: w.faint),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                const SizedBox(height: 2),
                Text(ada ? t(context).tapToEnlarge : t(context).photoNotOnThisPhone,
                    style: TextStyle(fontSize: 12, color: ada ? w.muted : w.badFg)),
              ],
            ),
          ),
          // Tanpa `onTake` berarti baca saja: tombol "foto ulang" pun tidak
          // ditampilkan, bukan sekadar dimatikan. Tombol mati yang tidak
          // pernah bisa ditekan hanya menimbulkan pertanyaan.
          if (onTake != null)
            TextButton.icon(
              onPressed: onTake,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(t(context).retakePhoto),
            ),
        ],
      ),
    );
  }
}

class _CastingPhoto extends ConsumerWidget {
  const _CastingPhoto({required this.uuid, required this.label});

  final String uuid;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final photo = ref.watch(_photoProvider(uuid)).value;
    // Still on its way, or the file was cleaned up by the system.
    if (photo == null || !File(photo.path).existsSync()) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: w.faint)),
        const SizedBox(height: 3),
        GestureDetector(
          onTap: () => _showPhotoFull(context, photo.path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(photo.path), height: 90, width: 120, fit: BoxFit.cover, cacheHeight: 270),
          ),
        ),
      ],
    );
  }
}

/// The big clock of the TM being poured.
///
/// Blue while pouring, grey while paused, red once past
/// [truckReminderAfter]; the ring fills toward that limit.
class _PourClock extends StatelessWidget {
  const _PourClock({required this.elapsed, required this.paused});

  final Duration elapsed;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final over = elapsed >= truckReminderAfter;
    final (bg, fg, label) = paused
        ? (w.surface2, w.muted, t(context).pausedLabel)
        : over
            ? (w.badBg, w.badFg, t(context).overMinutes(truckReminderAfter.inMinutes))
            : (w.brandSoft, w.brandStrong, t(context).pourTime);
    final progress = (elapsed.inSeconds / truckReminderAfter.inSeconds).clamp(0.0, 1.0);
    return AnimatedContainer(
      duration: Dimens.motionMedium,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(paused ? Icons.pause_circle_outline : over ? Icons.notifications_active_outlined : Icons.timer_outlined,
                        size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: fg)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(elapsed),
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              color: fg,
              backgroundColor: fg.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

String _clock(Object? iso) {
  final t = DateTime.tryParse('$iso');
  return t == null ? '–' : formatTime(t);
}

/// Pick why the pour is paused. Returns the server's reason code.
class _PauseReasonSheet extends StatelessWidget {
  const _PauseReasonSheet({required this.seq});

  final int seq;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    const icons = {
      'cabut_tremie': Icons.vertical_align_top,
      'tunggu_tm': Icons.local_shipping_outlined,
      'kendala_alat': Icons.build_outlined,
      'lainnya': Icons.more_horiz,
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).pauseTruckTitle(seq), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
            const SizedBox(height: 4),
            Text(t(context).pauseTruckBody, style: TextStyle(color: w.muted)),
            const SizedBox(height: 14),
            for (final e in pauseReasons(context).entries) ...[
              SizedBox(
                height: Dimens.minTouch + 4,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, e.key),
                  icon: Icon(icons[e.key]),
                  label: Text(e.value),
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

final _photoProvider = FutureProvider.autoDispose.family<PhotoRow?, String>((ref, uuid) => ref.watch(dbProvider).getPhoto(uuid));

/// New TM entry.
class _TruckSheet extends ConsumerStatefulWidget {
  const _TruckSheet({
    required this.seq,
    this.initial,
    required this.estimatedConcreteBefore,
    required this.theoreticalM3,
    required this.pouredSoFarM3,
    required this.takeTicketPhoto,
    required this.suppliers,
    required this.suppliersNarrowed,
    required this.supplierId,
    required this.supplierName,
  });

  final int seq;

  /// The TM being corrected, or null when a new one is arriving. Set = the
  /// fields start filled and the sheet saves back into that same TM.
  final Map<String, Object?>? initial;

  final double estimatedConcreteBefore;

  /// What this pile should take, and what the OTHER trucks have already put
  /// in, so the sheet can say where this truck lands before it is poured.
  final double theoreticalM3;
  final double pouredSoFarM3;

  final Future<String?> Function() takeTicketPhoto;

  /// Foto slump yang sudah diambil sebelum TM ini masuk, berikut jamnya.
  /// Isian ini terbuka dengan foto tersebut sudah terpasang.

  /// Concrete suppliers to offer, and the previous TM's choice as the
  /// preselected default.
  final List<Map<String, Object?>> suppliers;

  /// [suppliers] hanya berisi yang punya PO di proyek ini.
  ///
  /// Menentukan bunyi banner di atas pilihannya: daftar yang menyempit
  /// karena PO berbeda artinya dengan daftar yang memang belum disaring,
  /// dan yang di lapangan harus tahu yang mana — kalau tidak, pemasok yang
  /// hilang dari daftar terbaca sebagai aplikasi yang rusak.
  final bool suppliersNarrowed;

  final int? supplierId;
  final String? supplierName;

  @override
  ConsumerState<_TruckSheet> createState() => _TruckSheetState();
}

class _TruckSheetState extends ConsumerState<_TruckSheet> {
  /// A stored decimal ("7.00") as the field shows it ("7"): trailing zeros
  /// gone, comma for the separator. Typing over "7,00" to fix a slump is
  /// exactly the kind of small friction that makes people skip the fix.
  static String _asTyped(Object? v) {
    final d = toDoubleOrNull(v);
    if (d == null) return '';
    var t = d.toStringAsFixed(2);
    if (t.contains('.')) {
      t = t.replaceAll(RegExp(r'0+$'), '');
      t = t.replaceAll(RegExp(r'\.$'), '');
    }
    return t.replaceAll('.', ',');
  }

  bool get _editing => widget.initial != null;

  late final _truck = TextEditingController(text: widget.initial?['truckNo']?.toString() ?? '');
  late final _volume = TextEditingController(text: _asTyped(widget.initial?['volumeM3']));
  late final _slump = TextEditingController(text: _asTyped(widget.initial?['slumpCm']));
  late final _sounding = TextEditingController(text: _asTyped(widget.initial?['concreteDepthBeforeM']));
  late final _supplier = TextEditingController(text: widget.supplierName ?? '');
  late String? _photo = widget.initial?['ticketPhotoUuid']?.toString();
  /// Foto slump yang SUDAH ada pada TM ini; tidak pernah bertambah lagi.
  late final String? _slumpPhoto = widget.initial?['slumpPhotoUuid']?.toString();
  String? _error;

  // ── MENUTUP LEMBAR TIDAK BOLEH MEMBUANG KERJA LAPANGAN ────────────────
  //
  // Dilaporkan Daniel, 16 Okt 2026: QS memotret surat jalan, lalu menutup
  // lembar ini tanpa menekan Simpan. Fotonya sendiri sudah tersimpan dan
  // ikut naik lewat antrean foto — yang hilang hanya TAUTANNYA ke TM ini.
  // Akibatnya fotonya menjadi yatim di server dan TM-nya terbaca "tanpa
  // foto", dan satu kejadian butuh penelusuran SQL untuk menemukannya
  // kembali.
  //
  // Dialognya MENAWARKAN SIMPAN, bukan hanya memperingatkan: yang
  // diinginkan orangnya memang menyimpan, dan memperingatkan lalu
  // menyuruhnya mencari tombolnya sendiri hanya memindahkan masalahnya.
  //
  // Menutup dialog tanpa memilih TIDAK menutup lembarnya — hanya "Buang"
  // yang membuang, dan itu harus ditekan sadar.
  //
  // Polanya menyalin `attendance_form.dart`, bukan bentuk baru.

  /// Isian saat lembar DIBUKA. Diambil di `initState`, bukan `late` yang
  /// dibaca belakangan: yang dibaca belakangan akan merekam isian yang
  /// sudah diubah orangnya, dan pembandingnya selalu mengatakan "tidak ada
  /// perubahan".
  final Map<String, String?> _awal = {};

  @override
  void initState() {
    super.initState();
    _awal.addAll(_isianSekarang());
  }

  bool get _adaPerubahan {
    final kini = _isianSekarang();
    return kini.keys.any((k) => kini[k] != _awal[k]);
  }

  /// Tutup lembar; tanya lebih dahulu bila ada yang belum tersimpan.
  Future<void> _tutup() async {
    if (!_adaPerubahan) {
      Navigator.pop(context);
      return;
    }
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.save_outlined, size: 32),
        title: Text(t(c).unsavedTitle, textAlign: TextAlign.center),
        content: Text(t(c).unsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t(c).discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t(c).save),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (simpan == true) {
      // `_submit` sendiri yang menutup lembar bila isiannya sah. Yang tidak
      // sah membiarkannya terbuka dengan pesan galatnya — itu memang yang
      // diinginkan.
      _submit();
    } else if (simpan == false) {
      Navigator.pop(context);
    }
  }

  Map<String, String?> _isianSekarang() => {
        'truckNo': _truck.text,
        'volumeM3': _volume.text,
        'slumpCm': _slump.text,
        'sounding': _sounding.text,
        'supplier': _supplier.text,
        'photo': _photo,
        'slumpPhoto': _slumpPhoto,
        'pemasok': _supplierChoice?.toString(),
      };

  /// Chosen supplier id. `null` = belum dipilih.
  ///
  /// ───────────────────────────────────────────────────────────────────────
  /// TYPING A NAME IS ONLY OFFERED WHEN THERE IS NO LIST AT ALL
  /// ───────────────────────────────────────────────────────────────────────
  ///
  /// Reported by Daniel, 16 Oct 2026: this project has exactly two concrete
  /// suppliers, and a foreman still managed to enter "Jaya mix". The "other"
  /// item on the dropdown was the door, and the cost is not a messy list.
  /// A typed name matches no supplier row, so the casting carries a
  /// `supplierName` with no `supplierID`: it never reaches that supplier's
  /// recap, it never matches the delivery tickets, and the office only finds
  /// out while reconciling an invoice weeks later. That is how "SCG Jayamix"
  /// was born — a supplier that turned out never to have existed.
  ///
  /// So: when the app HAS a list, the list is the only way. If the real
  /// supplier is missing from it, the fix belongs in the office (mark the
  /// supplier "Pemasok beton", or issue the PO for this project) and the
  /// banner says so — otherwise the only way forward a foreman can see is
  /// to invent a name that nobody can trace.
  ///
  /// Free text survives for ONE case: no concrete supplier in the ERP at
  /// all. Without it, such a project could not log a casting.
  /// Beton SITE-MIX — diaduk di lokasi, bukan dari batching plant.
  ///
  /// Pilihan TETAP, bukan ketikan. Daniel, 16 Okt 2026: "seumur hidup cuma
  /// ada 1 proyek yang kaya gitu" — jarang, tetapi nyata, dan justru karena
  /// jarang ia tidak boleh dikembalikan menjadi isian bebas. Satu pilihan
  /// tetap menghasilkan satu nilai yang sama di seluruh HP; isian bebas
  /// menghasilkan "lokal", "Lokal", "site mix", "sitemix", dan "cor manual"
  /// untuk satu hal yang sama.
  ///
  /// Yang TERSIMPAN selalu [_namaLokal] — bukan labelnya di layar. Label
  /// boleh diterjemahkan; nilai yang tersimpan tidak, kalau tidak HP
  /// berbahasa Inggris akan menulis nama lain untuk beton yang sama.
  static const _lokal = -2;

  /// Nilai `supplierName` untuk site-mix. TETAP, tidak diterjemahkan.
  static const _namaLokal = 'Lokal';

  /// Where the pile lands if this truck's volume is poured, or null when
  /// nothing can be said (no typed volume, no theoretical volume).
  double? get _projectedOveruse {
    final v = parseNumber(_volume.text);
    if (v == null || v <= 0) return null;
    return overuseIfAdded(
      theoreticalM3: widget.theoreticalM3,
      pouredSoFarM3: widget.pouredSoFarM3,
      addM3: v,
    );
  }


  late int? _supplierChoice = widget.supplierId ??
      ((widget.supplierName ?? '') == _namaLokal ? _lokal : null);

  /// Nama yang DIKETIK pada build lama, dan tidak cocok dengan pemasok mana pun.
  ///
  /// Dibiarkan `null` pada pilihannya — bukan dipetakan ke butir dropdown.
  /// `DropdownButtonFormField` melempar assertion bila `value`-nya bukan
  /// salah satu butirnya, jadi memetakannya ke butir "Lainnya" yang sudah
  /// dibuang akan MERUSAK sheet ini tepat pada log yang paling perlu
  /// dibetulkan — log "Jaya mix" itu sendiri.
  ///
  /// Namanya tetap ditampilkan sebagai peringatan: menghilangkannya diam-diam
  /// berarti menghapus apa yang benar-benar dicatat lapangan.
  String? get _ketikanWarisan {
    final n = (widget.supplierName ?? '').trim();
    if (widget.suppliers.isEmpty || widget.supplierId != null) return null;
    if (n.isEmpty || n == _namaLokal) return null;
    return n;
  }

  /// An unusual volume was shown once; the second tap saves it.
  bool _volumeConfirmed = false;

  @override
  void dispose() {
    for (final c in [_truck, _volume, _slump, _sounding, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }


  /// Pilihan pemasok berubah — "Lokal" ditanyakan lebih dulu.
  ///
  /// Diminta Daniel, 16 Okt 2026: "takutnya salah klik loh". Butirnya duduk
  /// tepat di bawah pemasok sungguhan, dan jari yang meleset satu baris
  /// mengubah beton ready-mix menjadi site-mix — pada dokumen yang dipakai
  /// menagih, dan yang tidak akan pernah cocok dengan surat jalan mana pun
  /// sesudahnya.
  ///
  /// Hanya "Lokal" yang ditanyakan. Setiap pilihan yang ditanyakan membuat
  /// pertanyaannya makin tidak dibaca; yang perlu dipastikan di sini satu,
  /// yaitu yang artinya "tidak ada pemasok sama sekali".
  ///
  /// Dibatalkan berarti pilihannya TIDAK berubah — bukan kembali ke kosong.
  /// Kembali ke kosong, satu ketukan salah akan membuang pemasok yang sudah
  /// benar dan orangnya harus memilih ulang.
  Future<void> _pilihPemasok(int? v) async {
    if (v != _lokal) {
      setState(() => _supplierChoice = v);
      return;
    }
    final ya = await askConfirm(
      context,
      title: t(context).supplierLocalConfirmTitle,
      body: t(context).supplierLocalConfirmBody,
      confirmLabel: t(context).supplierLocalConfirmYes,
      icon: Icons.handyman_outlined,
    );
    if (!mounted || !ya) return;
    setState(() => _supplierChoice = v);
  }

  void _submit() {
    final volume = parseNumber(_volume.text);
    if (volume == null || volume <= 0 || volume > truckVolumeMaxM3) {
      setState(() => _error = t(context).volumeInvalid(decimalText(truckVolumeMaxM3, decimals: 0)));
      return;
    }
    if (volume > truckVolumeUsualMaxM3 && !_volumeConfirmed) {
      setState(() {
        _volumeConfirmed = true;
        _error = t(context).volumeUnusual(_decimal(volume));
      });
      return;
    }
    final slump = _slump.text.trim().isEmpty ? null : parseNumber(_slump.text);
    if (_slump.text.trim().isNotEmpty && (slump == null || slump < 0 || slump > 40)) {
      setState(() => _error = t(context).slumpInvalid);
      return;
    }
    final sounding = _sounding.text.trim().isEmpty ? null : parseNumber(_sounding.text);
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final picked = widget.suppliers.where((s) => toIntOrNull(s['id']) == _supplierChoice).firstOrNull;
    // With a list on hand, a supplier must be picked from it. Held HERE and
    // not left to the server: the server would reject the whole sync item
    // hours later, when this sheet is long closed and nobody can still tell
    // which casting it belonged to.
    final lokal = _supplierChoice == _lokal;
    if (widget.suppliers.isNotEmpty && picked == null && !lokal) {
      setState(() => _error = t(context).supplierMustBePicked);
      return;
    }
    Navigator.pop(context, {
      'truckNo': orNull(_truck),
      // Picked from the list: id + its name. Typed: name only.
      // Dipilih dari daftar: id + namanya. Site-mix: tanpa id, nama TETAP
      // `Lokal` (bukan labelnya di layar, yang boleh diterjemahkan).
      // Ketikan: nama saja, dan itu hanya mungkin bila daftarnya kosong.
      'supplierID': picked == null ? null : toIntOrNull(picked['id']),
      'supplierName': picked != null
          ? '${picked['name']}'
          : (lokal ? _namaLokal : orNull(_supplier)),
      'volumeM3': decimalText(volume),
      'slumpCm': slump == null ? null : decimalText(slump, decimals: 1),
      'concreteDepthBeforeM': sounding == null ? null : decimalText(sounding),
      'ticketPhotoUuid': _photo,
      'slumpPhotoUuid': _slumpPhoto,
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // `canPop: false` selalu, lalu kedirtian diperiksa di dalam
        // penanganannya. Dibuat `canPop: !_adaPerubahan`, nilainya hanya
        // dihitung ulang saat widget-nya dibangun kembali — dan mengetik di
        // `TextField` tidak membangun ulang apa pun, sehingga lembar yang
        // baru saja diisi tetap tertutup tanpa pertanyaan.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _tutup();
        },
        child: _isi(context),
      );

  // ───────────────────────────────────────────────────────────────────────
  // DUA TATA LETAK, SATU SUMBER UNTUK TIAP ISIAN
  // ───────────────────────────────────────────────────────────────────────
  //
  // TM DATANG ditanya SATU LAYAR SATU PERTANYAAN. Diminta Daniel, 27 Okt
  // 2026: sasarannya orang yang tidak terbiasa membaca banyak, dan lembar
  // berisi lima isian sekaligus menuntut orangnya memutuskan dari mana
  // mulai sebelum sempat menjawab apa pun.
  //
  // MEMBETULKAN TM TETAP SATU LEMBAR, dan itu disengaja. Yang membuka
  // lembar koreksi sudah tahu persis angka mana yang salah; memaksanya
  // melewati empat pertanyaan untuk sampai ke sana bukan menyederhanakan,
  // hanya memperpanjang.
  //
  // Tiap isian ditulis SEKALI sebagai fungsi di bawah dan dipakai kedua
  // tata letak. Menuliskannya dua kali berarti perbaikan berikutnya
  // mengenai satu jalur saja — dan yang terlewat adalah jalur yang lebih
  // jarang dibuka, yaitu yang paling lama tidak ketahuan.

  /// Pertanyaan ke berapa yang sedang tampil. Hanya dipakai saat TM BARU.
  int _step = 0;

  /// Pemasok terbawa dari TM sebelumnya, lalu orangnya menekan "Ubah".
  bool _paksaPemasok = false;

  /// Pemasok masih perlu ditanya: belum ada pilihan, tidak ada daftarnya
  /// sama sekali (harus diketik), atau orangnya minta mengubahnya.
  bool get _pemasokPerluDitanya =>
      widget.suppliers.isEmpty || _supplierChoice == null || _paksaPemasok;

  /// Urutan pertanyaan, masing-masing dengan PENANDA.
  ///
  /// Penandanya ada supaya `_maju` tidak perlu membandingkan fungsi untuk
  /// tahu sedang di pertanyaan mana. Perbandingan tear-off memang bekerja
  /// di Dart, tetapi kalau suatu saat tidak, gejalanya bukan galat
  /// melainkan pemeriksaan yang diam-diam tidak pernah jalan — dan itu
  /// jenis kegagalan yang paling mahal di berkas ini.
  List<({String tanda, List<Widget> Function() isi})> get _urutan => [
        (tanda: 'lambung', isi: _qLambung),
        (tanda: 'volume', isi: _qVolume),
        if (_pemasokPerluDitanya) (tanda: 'pemasok', isi: _qPemasok),
        (tanda: 'slump', isi: _qSlump),
        (tanda: 'penutup', isi: _qPenutup),
      ];

  Widget _tanya(String teks) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(teks,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
      );

  // ── Isian, satu sumber untuk kedua tata letak ──────────────────────────

  List<Widget> _isianFoto() => [
        // Two photos per TM. The delivery-note NUMBER is no longer typed:
        // it is already on the note in the photo, and a retyped number is
        // one more thing to get wrong at 2 a.m.
        _PhotoField(
          uuid: _photo,
          label: t(context).deliveryNote,
          emptyLabel: t(context).photoTicket,
          icon: Icons.receipt_long_outlined,
          onTake: () async {
            final f = await widget.takeTicketPhoto();
            if (f != null) setState(() => _photo = f);
          },
        ),
        // FOTO SLUMP TIDAK DIAMBIL LAGI — hanya ditampilkan bila sudah ada.
        //
        // Dicabut atas permintaan Daniel, 19 Oktober 2026. Angka slump
        // (`slumpCm`) tetap dicatat seperti biasa; yang hilang hanya
        // fotonya.
        //
        // Yang SUDAH terlanjur ada tetap dapat dibuka: 60 dari 382 TM
        // memilikinya. Foto yang masih tersimpan tetapi tidak ada satu
        // layar pun yang menampilkannya adalah bentuk kehilangan yang
        // paling sulit disadari — datanya ada, tetapi praktis lenyap.
        if (_slumpPhoto != null) ...[
          const SizedBox(height: 8),
          _PhotoField(
            uuid: _slumpPhoto,
            label: t(context).slumpTest,
            emptyLabel: t(context).photoSlump,
            icon: Icons.science_outlined,
          ),
        ],
      ];

  List<Widget> _isianLambung() => [
        TextField(
          controller: _truck,
          decoration: InputDecoration(labelText: t(context).hullNoField),
        ),
      ];

  List<Widget> _isianPemasok() => [
        if (widget.suppliers.isNotEmpty) ...[
          // PANDUAN PEMASOK ADA DI SINI, bukan lagi di lembar Data cor.
          //
          // Kedua banner ini dulu menemani pemilih pemasok di kepala
          // catatan, dan ikut hilang ketika pemilih itu dicabut —
          // sementara memilih pemasok justru pindah SELURUHNYA ke lembar
          // ini. Panduan yang tertinggal di layar yang sudah tidak ada
          // sama saja dengan tidak pernah ditulis.
          TerraBanner(
            kind: BannerKind.info,
            title: widget.suppliersNarrowed ? t(context).suppliersWithPo : t(context).noPoYet,
            body: widget.suppliersNarrowed ? t(context).suppliersWithPoBody : t(context).noPoYetBody,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: _supplierChoice,
            isExpanded: true,
            decoration: InputDecoration(labelText: t(context).truckSupplier),
            items: [
              for (final s in widget.suppliers)
                DropdownMenuItem<int?>(
                    value: toIntOrNull(s['id']),
                    child: Text('${s['name']}', overflow: TextOverflow.ellipsis)),
              // Paling bawah, sesudah pemasok sungguhan: site-mix adalah
              // perkecualian, dan letaknya mengatakan itu.
              DropdownMenuItem<int?>(value: _lokal, child: Text(t(context).supplierLocal)),
            ],
            onChanged: _pilihPemasok,
          ),
          // Jalan keluar ketika pemasok yang benar tidak ada di daftar,
          // ditulis DI TEMPAT jalan buntunya ditemui.
          const SizedBox(height: 8),
          TerraBanner(
            kind: BannerKind.info,
            title: t(context).supplierMissingTitle,
            body: t(context).supplierMissingBody,
          ),
          if (_ketikanWarisan != null) ...[
            const SizedBox(height: 8),
            TerraBanner(
              kind: BannerKind.warning,
              title: t(context).supplierTypedBefore,
              body: _ketikanWarisan!,
            ),
          ],
        ],
        if (widget.suppliers.isEmpty)
          TextField(
            controller: _supplier,
            decoration: InputDecoration(labelText: t(context).truckSupplier),
          ),
      ];

  List<Widget> _isianVolume() => [
        TextField(
          controller: _volume,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 2),
          decoration: InputDecoration(labelText: t(context).volumePouredHere, suffixText: 'm³'),
          onChanged: (_) {
            setState(() {
              if (_volumeConfirmed) _volumeConfirmed = false;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(t(context).volumeSharedHint,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5, height: 1.35)),
        ),
        ?_overuseBanner(),
      ];

  List<Widget> _isianSlump() => [
        TextField(
          controller: _slump,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 2, decimals: 1),
          decoration: InputDecoration(labelText: t(context).slumpField, suffixText: 'cm'),
        ),
      ];

  List<Widget> _isianSounding() => [
        TextField(
          controller: _sounding,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 3),
          decoration: InputDecoration(
            labelText: t(context).soundingBeforeOptional,
            suffixText: 'm',
            hintText: t(context)
                .estimateHint(widget.estimatedConcreteBefore.toStringAsFixed(2).replaceAll('.', ',')),
            // Kalimatnya sama persis dengan yang muncul di dialog sounding
            // sesudah. Dua penjelasan berbeda untuk satu pengukuran yang
            // sama membuat orang mengira keduanya mengukur hal berbeda.
            helperText: t(context).soundingQuestion,
            helperMaxLines: 2,
          ),
        ),
      ];

  // ── Pertanyaan ─────────────────────────────────────────────────────────

  List<Widget> _qLambung() => [_tanya(t(context).qTruckNo), ..._isianLambung()];

  List<Widget> _qVolume() => [_tanya(t(context).qVolume), ..._isianVolume()];

  List<Widget> _qPemasok() => [_tanya(t(context).qSupplier), ..._isianPemasok()];

  List<Widget> _qSlump() => [
        _tanya(t(context).qSlump),
        const SlumpDiagram(),
        const SizedBox(height: 12),
        ..._isianSlump(),
      ];

  List<Widget> _qPenutup() => [
        _tanya(t(context).qPhoto),
        ..._isianFoto(),
        // Pemasok yang TIDAK ditanya tetap diperlihatkan di sini.
        //
        // Yang terbawa diam-diam dari TM sebelumnya adalah yang paling
        // mudah salah tanpa ada yang menyadarinya — TM kelima dari
        // pemasok lain masuk atas nama pemasok TM keempat, dan selisihnya
        // baru ketahuan kantor saat mencocokkan tagihan.
        if (!_pemasokPerluDitanya) ...[
          const SizedBox(height: 12),
          TerraBanner(
            kind: BannerKind.info,
            title: t(context).supplierSameAsBefore(widget.supplierName ?? ''),
            action: TextButton(
              onPressed: () => setState(() {
                _paksaPemasok = true;
                // Pertanyaannya masuk SEBELUM slump dan penutup, jadi
                // indeksnya persis di posisi ketiga.
                _step = 2;
              }),
              child: Text(t(context).changeIt),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ..._isianSounding(),
      ];

  // ── Tata letak ─────────────────────────────────────────────────────────

  Widget _isi(BuildContext context) => _editing ? _lembarPenuh(context) : _bertahap(context);

  Widget _lembarPenuh(BuildContext context) => Padding(
        padding: sheetPadding(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(context).editTruck(widget.seq),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
              ..._isianFoto(),
              const SizedBox(height: 12),
              ..._isianLambung(),
              const SizedBox(height: 12),
              ..._isianPemasok(),
              const SizedBox(height: 12),
              ..._isianVolume(),
              const SizedBox(height: 12),
              ..._isianSlump(),
              const SizedBox(height: 12),
              ..._isianSounding(),
              const SizedBox(height: 18),
              SizedBox(
                height: Dimens.minTouch + 4,
                child: FilledButton(
                    onPressed: _submit, child: Text(t(context).saveChanges)),
              ),
            ],
          ),
        ),
      );

  Widget _bertahap(BuildContext context) {
    final langkah = _urutan;
    final i = _step.clamp(0, langkah.length - 1);
    final terakhir = i == langkah.length - 1;
    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).truckArrived(widget.seq),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            StepProgress(step: i + 1, total: langkah.length),
            const SizedBox(height: 16),
            if (_error != null) ...[
              TerraBanner(kind: BannerKind.danger, title: _error!),
              const SizedBox(height: 12),
            ],
            // PERTANYAANNYA BERGANTI DENGAN BERGERAK, bukan berkedip.
            //
            // Kosakatanya sama dengan `AnimatedFigure` di
            // `core/theme/motion.dart`: yang baru datang dari bawah sambil
            // memudar masuk. Di layar yang isinya berganti total tiap
            // ketukan, itu satu-satunya tanda bahwa yang berganti memang
            // pertanyaannya — bukan layarnya yang melompat sendiri.
            AnimatedSwitcher(
              duration: Dimens.motionMedium,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(langkah[i].tanda),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: langkah[i].isi(),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (i > 0) ...[
                  Expanded(
                    child: SizedBox(
                      height: Dimens.minTouch + 4,
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _error = null;
                          _step = i - 1;
                        }),
                        child: Text(t(context).backStep),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: Dimens.minTouch + 4,
                    child: FilledButton(
                      onPressed: terakhir ? _submit : () => _maju(i),
                      child: Text(terakhir ? t(context).saveTruck : t(context).nextStep),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Maju satu pertanyaan.
  ///
  /// Yang diperiksa di sini hanya KEHADIRAN jawabannya, bukan aturannya.
  /// Aturan sungguhan tetap satu tempat, di `_submit` — volume yang ganjil,
  /// pemasok yang wajib dipilih, site-mix yang ditanyakan ulang. Yang
  /// ditambahkan di sini cuma supaya galatnya muncul di layar PEMILIKNYA:
  /// pesan "volume belum diisi" yang tampil di layar foto tidak memberi
  /// tahu siapa pun harus kembali ke mana.
  void _maju(int i) {
    if (_urutan[i].tanda == 'volume') {
      // Kalimatnya SAMA PERSIS dengan yang dipakai `_submit` untuk aturan
      // yang sama. Dua kalimat berbeda untuk satu aturan membuat orangnya
      // mengira ada dua aturan.
      final v = parseNumber(_volume.text);
      if (v == null || v <= 0 || v > truckVolumeMaxM3) {
        setState(() => _error =
            t(context).volumeInvalid(decimalText(truckVolumeMaxM3, decimals: 0)));
        return;
      }
    }
    setState(() {
      _error = null;
      _step = i + 1;
    });
  }

  /// Di mana beton ini mendarat terhadap teoritis.
  ///
  /// MEMBERI TAHU, TIDAK PERNAH MENGHALANGI. Overbreak di atas 100% nyata
  /// terjadi di tanah yang jelek (Daniel, 12 Okt 2026), dan mandor yang
  /// tidak dapat menyimpan kenyataan akan mengetik angka yang lebih kecil
  /// supaya bisa lanjut — satu-satunya hasil yang lebih buruk daripada
  /// angka besar yang benar.
  Widget? _overuseBanner() {
    final over = _projectedOveruse;
    if (over == null || over <= volumeWarnPercent) return null;
    final used = widget.pouredSoFarM3 + (parseNumber(_volume.text) ?? 0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TerraBanner(
        kind: over > volumeLoudPercent ? BannerKind.danger : BannerKind.warning,
        icon: Icons.trending_up,
        title: t(context).overuseAheadTitle(over.toStringAsFixed(0)),
        body: t(context).overuseAheadBody(_decimal(used), _decimal(widget.theoreticalM3)),
      ),
    );
  }
}

/// Apa yang masih kurang sebelum catatan cor boleh ditutup.
enum _Kurang {
  /// Kedalaman ujung tremie saat mulai — ditanya lewat yang menyembul.
  tremie,
  mutu,

  /// Sounding sebelum TM PERTAMA, yang boleh dilewati saat TM itu dicatat.
  soundingAwal,
}

/// Jawaban lembar "Lengkapi dulu".
///
/// Dipisah karena tujuannya memang dua tempat: [doc] masuk ke kepala
/// catatan cor, [soundingAwal] masuk ke BARIS TM pertama. Dijadikan satu
/// peta, pemanggilnya harus menebak kunci mana milik siapa.
class _LengkapiHasil {
  const _LengkapiHasil({required this.doc, this.soundingAwal});

  final Map<String, Object?> doc;
  final double? soundingAwal;
}

/// Lembar "Lengkapi dulu" — menanyakan HANYA yang kurang, satu per layar.
///
/// DIMINTA DANIEL, 28 Okt 2026: "langsung tampilkan kartu untuk isi itu
/// boleh ga bang? jadi orang ga bingung dan harus cari cari lagi. kalau
/// memang ada multiple yauda minta dia input beberapa inputan gitu".
///
/// Bentuknya sengaja SAMA dengan lembar "Sebelum TM pertama" dan lembar
/// "TM datang": bar kemajuan, satu pertanyaan per layar, gambar yang
/// menunjukkan apa yang diukur. Yang sudah mengerti ketiganya di satu
/// tempat tidak perlu belajar lagi di tempat lain.
class _LengkapiSheet extends StatefulWidget {
  const _LengkapiSheet({
    required this.kurang,
    required this.bottomDepthM,
    required this.tremieLengthM,
    required this.grade,
    required this.defaultGrade,
  });

  final List<_Kurang> kurang;
  final double bottomDepthM;
  final double tremieLengthM;
  final double? grade;
  final double? defaultGrade;

  @override
  State<_LengkapiSheet> createState() => _LengkapiSheetState();
}

class _LengkapiSheetState extends State<_LengkapiSheet> {
  int _step = 0;
  final _stickOut = TextEditingController();
  final _sounding = TextEditingController();
  late final _grade = TextEditingController(
    text: (widget.grade ?? widget.defaultGrade) == null
        ? ''
        : _decimal(widget.grade ?? widget.defaultGrade, d: 1),
  );
  String? _error;

  @override
  void dispose() {
    _stickOut.dispose();
    _sounding.dispose();
    _grade.dispose();
    super.dispose();
  }

  double? get _depthM {
    final menyembul = parseNumber(_stickOut.text);
    if (menyembul == null) return null;
    return widget.tremieLengthM - menyembul;
  }

  static const _tanya =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3);
  static const _numerik = TextInputType.numberWithOptions(decimal: true);

  /// Isian langkah ke-[i] sudah sah? Pesannya, atau null bila sah.
  String? _periksa(_Kurang k) {
    switch (k) {
      case _Kurang.tremie:
        final d = _depthM;
        if (d == null) return t(context).stickOutRequired;
        final gap = widget.bottomDepthM - d;
        if (gap < -0.005) return t(context).stickOutTooDeep;
        if (gap > 5.005) return t(context).stickOutTooHigh(formatMeters(gap));
        return null;
      case _Kurang.mutu:
        final g = parseNumber(_grade.text);
        if (g == null || g <= 0 || g > 150) return 'Mutu beton tidak masuk akal.';
        return null;
      case _Kurang.soundingAwal:
        final v = parseNumber(_sounding.text);
        if (v == null) return t(context).soundingBeforeNeeded;
        // Muka beton tidak mungkin lebih dalam daripada dasar lubangnya.
        //
        // Angkanya dikirim TANPA satuan: kalimatnya sudah menuliskan " m"
        // sendiri, dan `formatMeters` akan membuatnya "29,50 m m".
        if (v > widget.bottomDepthM + 0.05) {
          return t(context).soundDeeperThanBottom(
            widget.bottomDepthM.toStringAsFixed(2).replaceAll('.', ','),
          );
        }
        return null;
    }
  }

  void _maju() {
    final galat = _periksa(widget.kurang[_step]);
    if (galat != null) {
      setState(() => _error = galat);
      return;
    }
    if (_step + 1 < widget.kurang.length) {
      setState(() {
        _error = null;
        _step += 1;
      });
      return;
    }
    _simpan();
  }

  void _simpan() {
    final doc = <String, Object?>{};
    double? soundingAwal;
    for (final k in widget.kurang) {
      switch (k) {
        case _Kurang.tremie:
          final d = _depthM!;
          final gap = widget.bottomDepthM - d;
          doc['tremieDepthStartM'] = decimalText(d);
          doc['tremieBottomGapM'] = decimalText(gap < 0 ? 0 : gap);
        case _Kurang.mutu:
          doc['concreteGrade'] = decimalText(parseNumber(_grade.text)!, decimals: 1);
        case _Kurang.soundingAwal:
          soundingAwal = parseNumber(_sounding.text);
      }
    }
    Navigator.pop(context, _LengkapiHasil(doc: doc, soundingAwal: soundingAwal));
  }

  List<Widget> _isi(_Kurang k) {
    switch (k) {
      case _Kurang.tremie:
        final dalam = _depthM;
        final gap = dalam == null ? null : widget.bottomDepthM - dalam;
        return [
          Text(t(context).stickOutQuestion, style: _tanya),
          const SizedBox(height: 10),
          const StickOutDiagram(),
          const SizedBox(height: 12),
          TextField(
            controller: _stickOut,
            autofocus: true,
            keyboardType: _numerik,
            inputFormatters: decimalInput(maxIntDigits: 3),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t(context).stickOutField,
              suffixText: 'm',
              helperText: t(context).stickOutBasis(formatMeters(widget.tremieLengthM)),
              helperMaxLines: 2,
            ),
          ),
          if (dalam != null && gap != null) ...[
            const SizedBox(height: 12),
            TerraBanner(
              kind: gap < -0.005 || gap > 5.005 ? BannerKind.warning : BannerKind.info,
              title: t(context).stickOutResult(formatMeters(dalam), formatMeters(gap)),
            ),
          ],
        ];
      case _Kurang.mutu:
        return [
          Text(t(context).gradeQuestion, style: _tanya),
          const SizedBox(height: 12),
          TextField(
            controller: _grade,
            autofocus: true,
            keyboardType: _numerik,
            inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1),
            decoration: InputDecoration(labelText: t(context).cellGrade, suffixText: 'MPa'),
          ),
          if (widget.defaultGrade != null) ...[
            const SizedBox(height: 12),
            TerraBanner(
              kind: BannerKind.info,
              title: t(context).defaultGrade(_decimal(widget.defaultGrade, d: 1)),
              body: t(context).defaultGradeBody,
            ),
          ],
        ];
      case _Kurang.soundingAwal:
        return [
          Text(t(context).qSoundingAwal, style: _tanya),
          const SizedBox(height: 10),
          const SoundingDiagram(),
          const SizedBox(height: 12),
          TextField(
            controller: _sounding,
            autofocus: true,
            keyboardType: _numerik,
            inputFormatters: decimalInput(maxIntDigits: 3),
            decoration: InputDecoration(
              labelText: t(context).concreteDepthField,
              suffixText: 'm',
              helperText: t(context).soundingQuestion,
              helperMaxLines: 2,
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurang[_step.clamp(0, widget.kurang.length - 1)];
    final terakhir = _step >= widget.kurang.length - 1;
    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).lengkapiTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t(context).lengkapiBody,
                style: TextStyle(color: context.colors.muted, height: 1.35)),
            const SizedBox(height: 10),
            // Satu ruas pun tetap digambar: yang kurang satu hal berhak
            // tahu bahwa memang tinggal satu.
            StepProgress(step: _step + 1, total: widget.kurang.length),
            const SizedBox(height: 16),
            if (_error != null) ...[
              TerraBanner(kind: BannerKind.danger, title: _error!),
              const SizedBox(height: 12),
            ],
            AnimatedSwitcher(
              duration: Dimens.motionMedium,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(k),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _isi(k),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (_step > 0) ...[
                  Expanded(
                    child: SizedBox(
                      height: Dimens.minTouch + 4,
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _error = null;
                          _step -= 1;
                        }),
                        child: Text(t(context).backStep),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: Dimens.minTouch + 4,
                    child: FilledButton(
                      onPressed: _maju,
                      child: Text(terakhir ? t(context).save : t(context).nextStep),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dua pertanyaan sebelum TM pertama — satu layar satu pertanyaan.
///
/// KENAPA YANG DITANYA BUKAN KEDALAMANNYA
///
/// Kolom lamanya meminta "kedalaman ujung tremie dari GS". Tidak ada
/// seorang pun di lokasi yang dapat MELIHAT angka itu: meteran tidak
/// diturunkan ke dalam lubang yang sebentar lagi diisi beton. Yang
/// benar-benar dilihat orang adalah berapa meter pipa MENYEMBUL di atas
/// tanah — dan kedalamannya tinggal dikurangkan dari panjang pipa yang
/// sudah tersusun, yang memang sudah diketahui aplikasi.
///
/// Terbukti pada 27 Okt 2026: ditanyai kedalamannya, jawabannya tidak
/// ada; ditanyai yang menyembul, jawabannya "kira-kira 1 m" dalam
/// hitungan detik. Pertanyaan yang salah membuat data yang benar
/// terlihat seperti data yang hilang.
///
/// Hasil hitungannya DIKEMBALIKAN KE LAYAR untuk dibenarkan, bukan
/// disimpan diam-diam. Yang menjawab berhak tahu angka apa yang jadi
/// atas namanya — dan satu salah ketik (10 m, bukan 1 m) langsung
/// terlihat di kalimat itu, bukan nanti di rekap kantor.
class _PourStartSheet extends StatefulWidget {
  const _PourStartSheet({
    required this.bottomDepthM,
    required this.tremieLengthM,
    required this.grade,
    required this.defaultGrade,
  });

  /// Dasar lubang dari GS; celahnya dihitung terhadap ini.
  final double bottomDepthM;

  /// Panjang pipa tremie yang SUDAH tersusun — dasar pengurangannya.
  final double tremieLengthM;

  final double? grade;
  final double? defaultGrade;

  @override
  State<_PourStartSheet> createState() => _PourStartSheetState();
}

class _PourStartSheetState extends State<_PourStartSheet> {
  int _step = 0;
  final _stickOut = TextEditingController();
  late final _grade = TextEditingController(
    text: (widget.grade ?? widget.defaultGrade) == null
        ? ''
        : _decimal(widget.grade ?? widget.defaultGrade, d: 1),
  );
  String? _error;

  @override
  void dispose() {
    _stickOut.dispose();
    _grade.dispose();
    super.dispose();
  }

  /// Kedalaman ujung tremie dari GS — DITURUNKAN, tidak pernah diketik.
  double? get _depthM {
    final menyembul = parseNumber(_stickOut.text);
    if (menyembul == null) return null;
    return widget.tremieLengthM - menyembul;
  }

  double? get _gapM {
    final d = _depthM;
    return d == null ? null : widget.bottomDepthM - d;
  }

  void _next() {
    final gap = _gapM;
    if (gap == null) {
      setState(() => _error = t(context).stickOutRequired);
      return;
    }
    // Batasnya SAMA dengan `_HeaderSheet._submit` dan dengan server
    // (`TREMIE_DALAM_SALAH`): 0 sampai 5 m di atas dasar lubang. Tiga
    // tempat satu angka; yang berbeda-beda akan menolak di satu tempat
    // dan menerima di tempat lain.
    if (gap < -0.005) {
      setState(() => _error = t(context).stickOutTooDeep);
      return;
    }
    if (gap > 5.005) {
      setState(() => _error = t(context).stickOutTooHigh(formatMeters(gap)));
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  void _save() {
    final grade = _grade.text.trim().isEmpty ? null : parseNumber(_grade.text);
    if (grade == null || grade <= 0 || grade > 150) {
      setState(() => _error = 'Mutu beton tidak masuk akal.');
      return;
    }
    final dalam = _depthM!;
    final gap = widget.bottomDepthM - dalam;
    Navigator.pop(context, {
      'concreteGrade': decimalText(grade, decimals: 1),
      'tremieDepthStartM': decimalText(dalam),
      // Celahnya ikut dikirim, sama seperti `_HeaderSheet`: server lama
      // tidak mengenal kolom terukurnya dan hitungannya mundur ke sini.
      'tremieBottomGapM': decimalText(gap < 0 ? 0 : gap),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).pourStartTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            StepProgress(step: _step + 1, total: 2),
            const SizedBox(height: 14),
            if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
            // Pertanyaannya berganti dengan BERGERAK — kosakata yang sama
            // dengan lembar TM dan dengan `AnimatedFigure`.
            AnimatedSwitcher(
              duration: Dimens.motionMedium,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(_step),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _step == 0 ? _langkahTremie() : _langkahMutu(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _tanya =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3);
  static const _numerik = TextInputType.numberWithOptions(decimal: true);

  List<Widget> _langkahTremie() {
    final dalam = _depthM;
    final gap = _gapM;
    return [
      Text(t(context).stickOutQuestion, style: _tanya),
      const SizedBox(height: 10),
      const StickOutDiagram(),
      const SizedBox(height: 12),
      TextField(
        controller: _stickOut,
        autofocus: true,
        keyboardType: _numerik,
        inputFormatters: decimalInput(maxIntDigits: 3),
        // Hitungannya ikut berubah sambil diketik: itulah yang membuat
        // salah ketik terlihat sebelum disimpan.
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: t(context).stickOutField,
          suffixText: 'm',
          helperText: t(context).stickOutBasis(formatMeters(widget.tremieLengthM)),
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 12),
      // HASIL HITUNGANNYA IKUT BERGERAK SAAT ANGKANYA BERUBAH.
      //
      // Alasannya sama dengan `AnimatedFigure`: angka yang berganti harus
      // TERLIHAT berganti. Di sini itu bukan hiasan — kalimat ini satu-
      // satunya tempat salah ketik "10" yang dimaksud "1" kelihatan, dan
      // kalimat yang berganti diam-diam adalah kalimat yang tidak dibaca.
      AnimatedSwitcher(
        duration: Dimens.motionMedium,
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(sizeFactor: animation, child: child),
        ),
        child: dalam == null || gap == null
            ? const SizedBox.shrink()
            : TerraBanner(
                key: ValueKey('${formatMeters(dalam)}|${formatMeters(gap)}'),
                kind: gap < -0.005 || gap > 5.005 ? BannerKind.warning : BannerKind.info,
                title: t(context).stickOutResult(formatMeters(dalam), formatMeters(gap)),
              ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        height: Dimens.minTouch + 4,
        child: FilledButton(onPressed: _next, child: Text(t(context).nextStep)),
      ),
    ];
  }

  List<Widget> _langkahMutu() => [
        Text(t(context).gradeQuestion, style: _tanya),
        const SizedBox(height: 12),
        TextField(
          controller: _grade,
          autofocus: true,
          keyboardType: _numerik,
          inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1),
          decoration: InputDecoration(labelText: t(context).cellGrade, suffixText: 'MPa'),
        ),
        if (widget.defaultGrade != null) ...[
          const SizedBox(height: 12),
          TerraBanner(
            kind: BannerKind.info,
            title: t(context).defaultGrade(_decimal(widget.defaultGrade, d: 1)),
            body: t(context).defaultGradeBody,
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: Dimens.minTouch + 4,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _error = null;
                    _step = 0;
                  }),
                  child: Text(t(context).backStep),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: Dimens.minTouch + 4,
                child: FilledButton(onPressed: _save, child: Text(t(context).save)),
              ),
            ),
          ],
        ),
      ];
}

/// Data cor: mutu beton, kedalaman tremie, catatan.
///
/// TANPA PEMASOK. Pemasok dicatat per TM, di `_TruckSheet`, dan hanya di
/// sana — lihat catatan di `_editHeader`. Kendali pemasok di lembar ini
/// pernah ada dan sudah dicabut: isinya tidak lagi disimpan ke mana pun,
/// jadi ia hanya terlihat bekerja.
class _HeaderSheet extends StatefulWidget {
  const _HeaderSheet({
    required this.grade,
    required this.defaultGrade,
    required this.bottomDepthM,
    required this.tremieDepthStartM,
    required this.note,
  });

  final double? grade;
  final double? defaultGrade;

  /// Dasar lubang dari GS. Celahnya dihitung dari sini, tidak diisi tangan.
  final double bottomDepthM;

  /// Kedalaman ujung bawah tremie dari GS, hasil ukur. Kosong = belum diukur.
  final double? tremieDepthStartM;
  final String? note;

  @override
  State<_HeaderSheet> createState() => _HeaderSheetState();
}

class _HeaderSheetState extends State<_HeaderSheet> {
  late final _grade = TextEditingController(text: widget.grade == null ? '' : _decimal(widget.grade, d: 1));
  late final _gap = TextEditingController(
      text: widget.tremieDepthStartM == null ? '' : _decimal(widget.tremieDepthStartM));
  late final _note = TextEditingController(text: widget.note ?? '');
  String? _error;

  // ── MENUTUP LEMBAR TIDAK BOLEH MEMBUANG KERJA LAPANGAN ────────────────
  //
  // Dilaporkan Daniel, 16 Okt 2026: QS memotret surat jalan, lalu menutup
  // lembar ini tanpa menekan Simpan. Fotonya sendiri sudah tersimpan dan
  // ikut naik lewat antrean foto — yang hilang hanya TAUTANNYA ke TM ini.
  // Akibatnya fotonya menjadi yatim di server dan TM-nya terbaca "tanpa
  // foto", dan satu kejadian butuh penelusuran SQL untuk menemukannya
  // kembali.
  //
  // Dialognya MENAWARKAN SIMPAN, bukan hanya memperingatkan: yang
  // diinginkan orangnya memang menyimpan, dan memperingatkan lalu
  // menyuruhnya mencari tombolnya sendiri hanya memindahkan masalahnya.
  //
  // Menutup dialog tanpa memilih TIDAK menutup lembarnya — hanya "Buang"
  // yang membuang, dan itu harus ditekan sadar.
  //
  // Polanya menyalin `attendance_form.dart`, bukan bentuk baru.

  /// Isian saat lembar DIBUKA. Diambil di `initState`, bukan `late` yang
  /// dibaca belakangan: yang dibaca belakangan akan merekam isian yang
  /// sudah diubah orangnya, dan pembandingnya selalu mengatakan "tidak ada
  /// perubahan".
  final Map<String, String?> _awal = {};

  @override
  void initState() {
    super.initState();
    _awal.addAll(_isianSekarang());
  }

  bool get _adaPerubahan {
    final kini = _isianSekarang();
    return kini.keys.any((k) => kini[k] != _awal[k]);
  }

  /// Tutup lembar; tanya lebih dahulu bila ada yang belum tersimpan.
  Future<void> _tutup() async {
    if (!_adaPerubahan) {
      Navigator.pop(context);
      return;
    }
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.save_outlined, size: 32),
        title: Text(t(c).unsavedTitle, textAlign: TextAlign.center),
        content: Text(t(c).unsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t(c).discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t(c).save),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (simpan == true) {
      // `_submit` sendiri yang menutup lembar bila isiannya sah. Yang tidak
      // sah membiarkannya terbuka dengan pesan galatnya — itu memang yang
      // diinginkan.
      _submit();
    } else if (simpan == false) {
      Navigator.pop(context);
    }
  }

  Map<String, String?> _isianSekarang() => {
        'grade': _grade.text,
        'gap': _gap.text,
        'note': _note.text,
      };

  @override
  void dispose() {
    for (final c in [_grade, _gap, _note]) {
      c.dispose();
    }
    super.dispose();
  }



  void _submit() {
    final grade = _grade.text.trim().isEmpty ? null : parseNumber(_grade.text);
    if (_grade.text.trim().isNotEmpty && (grade == null || grade <= 0 || grade > 150)) {
      setState(() => _error = 'Mutu beton tidak masuk akal.');
      return;
    }
    // DIUKUR, bukan diasumsikan: yang diisi QS adalah kedalaman ujung bawah
    // tremie dari GS, dan celahnya dihitung. Dua angka yang menyatakan hal
    // yang sama, dua-duanya diisi tangan, pasti berselisih suatu saat — dan
    // tidak ada aturan yang menentukan mana yang dipakai hitungan.
    final dalam = parseNumber(_gap.text);
    if (dalam == null) {
      setState(() => _error = t(context).tremieDepthRequired);
      return;
    }
    final gap = widget.bottomDepthM - dalam;
    // BATAS ATASNYA 5 M, BUKAN 1 M — disamakan dengan server.
    //
    // Sampai 27 Okt 2026 batasnya di sini 1 m, sementara server menerima
    // sampai 5 m di atas dasar lubang. Angka 1 m itu bukan batas fisik:
    // ia ASUMSI bawaan yang dipakai saat kedalamannya belum diukur, dan
    // ia menyelinap ke sini sebagai batas.
    //
    // Akibatnya kolom yang seluruh gunanya MENGGANTI asumsi dengan hasil
    // ukur hanya mau menerima angka yang sependapat dengan asumsinya.
    // Pada SP.B58 ujung tremie sungguhan berada 1,90 m di atas dasar
    // lubang; formulirnya menjawab "tidak masuk akal", dan satu-satunya
    // cara menutup log adalah mengetik angka yang tidak benar. Penjaga
    // yang memaksa orang berbohong lebih buruk daripada tidak ada
    // penjaga.
    //
    // 5 m tetap batas kewarasan: lebih dari itu tremienya memang salah
    // susun, dan server menolaknya juga.
    if (gap < -0.005 || gap > 5.005) {
      setState(() => _error = t(context).tremieDepthInvalid(formatMeters(widget.bottomDepthM)));
      return;
    }
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(context, {
      'concreteGrade': grade == null ? null : decimalText(grade, decimals: 1),
      'tremieDepthStartM': decimalText(dalam),
      // Celahnya ikut dikirim: server lama tidak mengenal kolom terukurnya,
      // dan hitungannya mundur ke sini.
      'tremieBottomGapM': decimalText(gap < 0 ? 0 : gap),
      'note': orNull(_note),
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // `canPop: false` selalu, lalu kedirtian diperiksa di dalam
        // penanganannya. Dibuat `canPop: !_adaPerubahan`, nilainya hanya
        // dihitung ulang saat widget-nya dibangun kembali — dan mengetik di
        // `TextField` tidak membangun ulang apa pun, sehingga lembar yang
        // baru saja diisi tetap tertutup tanpa pertanyaan.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _tutup();
        },
        child: _isi(context),
      );

  Widget _isi(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).castDataTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
            if (widget.defaultGrade != null)
              TerraBanner(
                kind: BannerKind.info,
                title: t(context).defaultGrade(_decimal(widget.defaultGrade, d: 1)),
                body: t(context).defaultGradeBody,
              ),
            TextField(controller: _grade, keyboardType: numeric, inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1), decoration: InputDecoration(labelText: t(context).cellGrade, suffixText: 'MPa')),
            const SizedBox(height: 12),
            TextField(
              controller: _gap,
              keyboardType: numeric,
              inputFormatters: decimalInput(maxIntDigits: 3),
              decoration: InputDecoration(
                labelText: t(context).tremieDepthField,
                suffixText: 'm',
                helperText: t(context).tremieDepthHint(formatMeters(widget.bottomDepthM)),
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, maxLines: 3, decoration: InputDecoration(labelText: t(context).noteField)),
            const SizedBox(height: 18),
            SizedBox(height: Dimens.minTouch + 4, child: FilledButton(onPressed: _submit, child: Text(t(context).save))),
          ],
        ),
      ),
    );
  }
}

/// "+4%" / "−50%" — seberapa jauh lubangnya lebih besar daripada gambar.
///
/// DITAMPILKAN SEBAGAI PERSEN, BUKAN SEBAGAI ANGKA RASIO. "1,04" menuntut
/// pembacanya tahu bahwa 1,00 berarti pas, lalu mengalikan selisihnya
/// seratus. Yang tidak tahu membacanya sebagai "1,04 meter", atau tidak
/// membacanya sama sekali.
///
/// Bentuk yang sama dipakai di kartu TM DAN di peringatan rasio yang
/// melompat, supaya yang dibandingkan orangnya memang dua angka yang
/// ditulis dengan cara yang sama.
String _persenLebih(double ratio) {
  final persen = ((ratio - 1) * 100).round();
  return '${persen >= 0 ? '+' : '−'}${persen.abs()}%';
}

/// "kedalaman 3,00–6,00 m", or with the part above ground spelled out.
String _hangText(BuildContext context, double top, double bottom) {
  String m(double v) => '${v.abs().toStringAsFixed(2).replaceAll('.', ',')}\u00A0';
  if (bottom <= 0) return t(context).hangAboveGs(m(top), m(bottom));
  if (top < 0) return t(context).hangAcrossGs(m(top), m(bottom));
  return t(context).hangDepth(m(top), m(bottom));
}

/// What the finish dialog came back with. `note` is the reason a pile was
/// closed before cut-off, or null when there is nothing to explain.
class _FinishResult {
  const _FinishResult({this.note});

  final String? note;
}

/// Confirm "Selesai cor".
///
/// A pile closed below cut-off is a SHORT PILE, and concrete sets: there is no
/// undo in the field. So the friction is graded by how short it is.
///
///   * at or past cut-off     → plain confirmation;
///   * short by ≤ [_slackM]   → warning, still one tap (finishing a few
///     centimetres under cut-off happens, and the trim covers it);
///   * short by more          → the dialog refuses to let "Tetap selesai" be
///     the easy button: a REASON must be picked first, "Belum — lanjut cor"
///     is the filled one, and the shortfall is spelled out in m³ AND in
///     truckloads, because "kurang 10,40 m" does not read as "4 TM lagi".
///
/// It is never blocked outright: pours really do get abandoned (blocked
/// tremie, no truck, collapsed hole), and a foreman who cannot close a failed
/// log would invent data instead.
class _FinishDialog extends StatefulWidget {
  const _FinishDialog({
    required this.code,
    required this.short,
    required this.missingM,
    required this.levelDepthM,
    required this.cutOffDepthM,
    required this.measured,
    required this.pouredM3,
    required this.theoreticalM3,
    required this.areaM2,
    required this.averageTruckM3,
  });

  final String code;
  final bool short;

  /// How far the concrete surface still is BELOW cut-off, in metres.
  final double missingM;
  final double levelDepthM;
  final double cutOffDepthM;

  /// The level came from a sounding, not from the poured volume.
  final bool measured;
  final double pouredM3;
  final double theoreticalM3;
  final double areaM2;

  /// Average volume of the trucks on this pile — null when there is none yet.
  final double? averageTruckM3;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  /// Codes stay English; only what the foreman reads is Indonesian.
  List<(String, String, IconData)> _reasonList(BuildContext context) => [
        ('tremie_tersumbat', t(context).stopTremieBlocked, Icons.block),
        ('tm_tidak_datang', t(context).stopNoTruck, Icons.local_shipping_outlined),
        ('lubang_runtuh', t(context).stopHoleCollapse, Icons.terrain_outlined),
        ('alat_cuaca', t(context).stopPlantWeather, Icons.bolt_outlined),
        ('lainnya', t(context).other, Icons.edit_outlined),
      ];

  String? _reason;
  final _detail = TextEditingController();

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  /// Shortfall in m³ and truckloads, and whether it needs explaining.
  ({double volumeM3, int trucks, bool mustExplain}) get _short => shortfallToCutOff(
        missingM: widget.missingM,
        areaM2: widget.areaM2,
        averageTruckM3: widget.averageTruckM3,
      );

  bool get _mustExplain => widget.short && _short.mustExplain;

  bool get _canFinish {
    if (!_mustExplain) return true;
    if (_reason == null) return false;
    return _reason != 'lainnya' || _detail.text.trim().isNotEmpty;
  }

  String? get _note {
    if (!_mustExplain || _reason == null) return null;
    final label = _reasonList(context).firstWhere((r) => r.$1 == _reason).$2;
    final detail = _detail.text.trim();
    final why = _reason == 'lainnya' ? detail : (detail.isEmpty ? label : t(context).labelDetail(label, detail));
    return t(context).stoppedBeforeCutOff(
        formatMeters(widget.missingM), _decimal(_short.volumeM3), why);
  }

  Widget _reasonRow(String code, String label, IconData icon) {
    final w = context.colors;
    final picked = _reason == code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: picked ? w.brandSoft : w.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: picked ? w.brand : w.border, width: picked ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _reason = code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: picked ? w.brandStrong : w.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontWeight: picked ? FontWeight.w800 : FontWeight.w600,
                        color: picked ? w.brandStrong : w.ink,
                      )),
                ),
                if (picked) Icon(Icons.check_circle, size: 20, color: w.brandStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final percent = widget.theoreticalM3 <= 0 ? null : widget.pouredM3 / widget.theoreticalM3 * 100;
    return AlertDialog(
      icon: widget.short
          ? Icon(Icons.warning_amber_rounded, size: 32, color: w.badFg)
          : Icon(Icons.check_circle_outline, size: 32, color: w.okFg),
      title: Text(widget.short ? t(context).belowCutOffTitle : t(context).finishCastingOf(widget.code),
          textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.short) ...[
              TerraBanner(
                kind: _mustExplain ? BannerKind.danger : BannerKind.warning,
                icon: Icons.straighten,
                title: t(context).shortfallTitle(_decimal(_short.volumeM3), _short.trucks),
                body: [
                  t(context).shortfallLine1(formatMeters(widget.levelDepthM),
                      formatMeters(widget.cutOffDepthM), formatMeters(widget.missingM)),
                  t(context).shortfallLine2(
                    _decimal(widget.pouredM3),
                    _decimal(widget.theoreticalM3),
                    percent == null ? '' : t(context).percentSuffix(percent.toStringAsFixed(0)),
                  ),
                  if (!widget.measured) t(context).estimateSoundToBeSure,
                ].join('\n'),
              ),
              const SizedBox(height: 12),
            ],
            if (_mustExplain) ...[
              Text(t(context).shortPileWarning, style: TextStyle(color: w.ink, height: 1.4)),
              const SizedBox(height: 12),
              for (final (code, label, icon) in _reasonList(context)) _reasonRow(code, label, icon),
              if (_reason != null)
                TextField(
                  controller: _detail,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _reason == 'lainnya' ? t(context).reasonRequired : t(context).detailOptional,
                    hintText: t(context).reasonHint,
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ] else
              Text(
                widget.short ? t(context).shortABitBody : t(context).finishedBody,
                style: TextStyle(color: w.muted, height: 1.4),
              ),
          ],
        ),
      ),
      // The dangerous button is the quiet one: when the pile is far short,
      // "Belum — lanjut cor" is what the thumb lands on.
      actions: _mustExplain
          ? [
              TextButton(
                onPressed: _canFinish ? () => Navigator.pop(context, _FinishResult(note: _note)) : null,
                child: Text(t(context).finishAnyway, style: TextStyle(color: _canFinish ? w.badFg : w.faint)),
              ),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(t(context).notYetKeepPouring)),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context).notYet)),
              FilledButton(
                onPressed: () => Navigator.pop(context, const _FinishResult()),
                child: Text(widget.short ? t(context).finishAnyway : t(context).finish),
              ),
            ],
    );
  }
}
