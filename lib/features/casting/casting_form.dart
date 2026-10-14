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
    await _muatSlumpMenunggu();
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
  Future<void> _toggleRemoved(String segmentUuid, int? seq) async {
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
    // Prefilled from the previous TM, else from Data cor, so the common
    // case (one plant all day) costs no extra tap.
    final lastTruck = _trucks.lastOrNull;
    final defaultSupplierId = toIntOrNull(lastTruck?['supplierID']) ?? toIntOrNull(_doc!['supplierID']);
    final defaultSupplierName = (lastTruck?['supplierName'] ?? _doc!['supplierName'])?.toString();
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
        takeSlumpPhoto: _takeSlumpPhoto,
        // Foto slump yang sudah diambil saat TM sebelumnya masih dituang.
        slumpPhotoUuid: _slumpMenunggu?.uuid,
        slumpPhotoAt: _slumpMenunggu?.at,
        suppliers: offer.suppliers,
        supplierId: defaultSupplierId,
        supplierName: defaultSupplierName,
      ),
    );
    if (result == null) return;
    // Titipannya terpakai: kalau tidak dibuang, foto yang sama akan menempel
    // lagi pada TM berikutnya.
    if (_slumpMenunggu != null && result['slumpPhotoUuid'] == _slumpMenunggu!.uuid) {
      await _simpanSlumpMenunggu(null);
    }
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
        takeSlumpPhoto: _takeSlumpPhoto,
        suppliers: offer.suppliers,
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

  /// The slump cone, photographed with the tape against it. The typed figure
  /// stays, but now it has its evidence.
  Future<String?> _takeSlumpPhoto() async {
    final p = ref.read(userProvider);
    if (p == null) return null;
    final f = await takePhoto(db: ref.read(dbProvider), userId: p.id, kind: 'slump_tm');
    return f?.uuid;
  }

  // ---------------------------------------------------------------------
  // Foto slump yang diambil LEBIH DULU
  // ---------------------------------------------------------------------
  //
  // Uji slump TM berikutnya biasa dilakukan saat TM sekarang masih dituang —
  // artinya pada saat fotonya diambil, isian TM itu belum ada, dan tidak ada
  // tempat untuk menaruhnya.
  //
  // Yang TIDAK dipilih: mengizinkan ambil dari galeri. Nilai foto slump di
  // berkas mutu justru terletak pada kepastian kapan ia diambil; begitu
  // galeri terbuka, foto mana pun bisa masuk — slump kemarin, slump titik
  // sebelah — dan tidak ada yang bisa membedakannya belakangan.
  //
  // Jadi fotonya tetap lewat kamera aplikasi, hanya saja diparkir sampai TM
  // yang bersangkutan dibuka. Penitipannya LOKAL: tidak pernah ikut
  // dikirim, jadi tidak ada perubahan apa pun di server. Fotonya sendiri
  // sudah naik lewat antrean foto seperti biasa.

  String get _kunciSlumpMenunggu => 'slump_menunggu:${widget.uuid}';

  /// Foto slump yang menunggu TM berikutnya: uuid foto dan jam pengambilannya.
  ({String uuid, DateTime at})? _slumpMenunggu;

  Future<void> _muatSlumpMenunggu() async {
    final teks = await ref.read(dbProvider).readMeta(_kunciSlumpMenunggu);
    final bagian = (teks ?? '').split('|');
    final kapan = bagian.length < 2 ? null : DateTime.tryParse(bagian[1]);
    if (!mounted) return;
    setState(() => _slumpMenunggu = kapan == null ? null : (uuid: bagian[0], at: kapan));
  }

  Future<void> _simpanSlumpMenunggu(({String uuid, DateTime at})? nilai) async {
    await ref.read(dbProvider).writeMeta(
          _kunciSlumpMenunggu,
          nilai == null ? null : '${nilai.uuid}|${nilai.at.toIso8601String()}',
        );
    if (mounted) setState(() => _slumpMenunggu = nilai);
  }

  Future<void> _fotoSlumpDuluan() async {
    final uuid = await _takeSlumpPhoto();
    if (uuid == null) return;
    await _simpanSlumpMenunggu((uuid: uuid, at: DateTime.now()));
    if (mounted) showSnack(context, t(context).slumpPhotoParked, icon: Icons.science_outlined);
  }

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
    final v = await _askNumber(
      title: t(context).soundingAfter('$seq'),
      label: t(context).concreteDepthField,
      icon: Icons.local_shipping_outlined,
      suffix: 'm',
      maxValue: 200,
      initial: toDoubleOrNull(truck['concreteDepthAfterM']),
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
    // The sounding is the gate before the next TM and before "Selesai cor":
    // report whether it was really stored, not just that it was typed.
    return _updateTruck('${truck['uuid']}', (t) => t['concreteDepthAfterM'] = decimalText(value));
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

  Future<void> _editHeader() async {
    // Concrete suppliers marked in the ERP (Pemasok → "Pemasok beton").
    // Only those with a PO in this project, when there are any.
    final offer = suppliersForProject(
      await ref.read(dbProvider).listMaster('supplier'),
      toIntOrNull(_pilePoint!['projectID']),
      keepId: toIntOrNull(_doc!['supplierID']),
    );
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _HeaderSheet(
        grade: toDoubleOrNull(_doc!['concreteGrade']),
        defaultGrade: toDoubleOrNull(_pilePoint!['concreteGrade']) ?? toDoubleOrNull(_project?['defaultConcreteGrade']),
        suppliers: offer.suppliers,
        suppliersNarrowed: offer.narrowed,
        supplierId: toIntOrNull(_doc!['supplierID']),
        supplier: _doc!['supplierName']?.toString(),
        bottomDepthM: _castingState.geometry.bottomDepthM,
        tremieDepthStartM: toDoubleOrNull(_doc!['tremieDepthStartM']),
        note: _doc!['note']?.toString(),
      ),
    );
    if (result == null) return;
    if (!await _update((d) => d.addAll(result))) return;
    if (mounted) showSnack(context, t(context).castDataSaved);
  }

  Future<void> _finishCasting() async {
    final unsounded = _unsoundedTruck;
    if (unsounded != null && !await _askSoundingAfter(unsounded)) return;

    // Dua angka yang hanya dapat diukur di lokasi, dan yang tanpanya seluruh
    // angka tertanam log ini kosong selamanya. Ditahan DI SINI, bukan
    // dibiarkan ditolak server sesudah QS pulang: yang menolak nanti tidak
    // dapat lagi menurunkan meteran ke dalam lubang.
    if (toDoubleOrNull(_doc!['tremieDepthStartM']) == null) {
      if (mounted) showSnack(context, t(context).tremieDepthNeeded);
      return;
    }
    final pertama = _trucks.isEmpty
        ? null
        : _trucks.reduce((a, b) => (toIntOrNull(a['seq']) ?? 0) <= (toIntOrNull(b['seq']) ?? 0) ? a : b);
    if (pertama != null && toDoubleOrNull(pertama['concreteDepthBeforeM']) == null) {
      if (mounted) showSnack(context, t(context).soundingBeforeNeeded);
      return;
    }

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

          _SummaryCard(geometry: g, castingState: k, grade: _grade, supplier: _doc!['supplierName']?.toString(), onEdit: _readOnly ? null : _editHeader),
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
            onToggleRemoved: _toggleRemoved,
          ),

          // --- recommendation -----------------------------------------------
          if (seq > 0 && !_finished) _suggestionCard(k, seq),

          // --- TM ---------------------------------------------------------
          _SectionTitle(t(context).trucksSection, t(context).trucksSectionBody(_trucks.length, _decimal(k.totalVolumeM3))),
          if (!_readOnly && !_finished)
            _SlumpMenungguCard(
              menunggu: _slumpMenunggu,
              onAmbil: _fotoSlumpDuluan,
              onBuang: _slumpMenunggu == null ? null : () => _simpanSlumpMenunggu(null),
            ),
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
                        child: OutlinedButton(onPressed: _finishCasting, child: Text(t(context).finishCasting)),
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
                                  : FilledButton.icon(
                                      onPressed: _tremie.isEmpty ? null : _newTruck,
                                      icon: const Icon(Icons.local_shipping_outlined),
                                      label: Text(_tremie.isEmpty ? t(context).tremieFirst : t(context).truckArrived(seq + 1)),
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
          if (ratio != null) value(t(context).overbreakRatio, _decimal(ratio)),
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
    required this.onTake,
    this.note,
  });

  final String? uuid;
  final String label;
  final String emptyLabel;

  /// Keterangan pengganti "ketuk untuk memperbesar" — dipakai saat fotonya
  /// datang dari titipan, supaya tidak ada yang bingung kenapa isian TM baru
  /// sudah ada fotonya.
  final String? note;
  final IconData icon;
  final Future<void> Function() onTake;

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
                Text(ada ? (note ?? t(context).tapToEnlarge) : t(context).photoNotOnThisPhone,
                    style: TextStyle(fontSize: 12, color: ada ? w.muted : w.badFg)),
              ],
            ),
          ),
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

/// Foto slump yang sudah diambil tetapi TM-nya belum masuk.
///
/// Muncul sebagai ajakan selama belum ada, dan sebagai pratinjau begitu ada —
/// supaya QS tahu fotonya sudah di tangan aplikasi dan tidak memotret dua
/// kali, serta bisa membuangnya kalau ternyata keliru.
class _SlumpMenungguCard extends ConsumerWidget {
  const _SlumpMenungguCard({required this.menunggu, required this.onAmbil, required this.onBuang});

  final ({String uuid, DateTime at})? menunggu;
  final VoidCallback onAmbil;
  final VoidCallback? onBuang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final m = menunggu;
    if (m == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          onPressed: onAmbil,
          icon: const Icon(Icons.science_outlined),
          label: Text(t(context).slumpPhotoAhead),
        ),
      );
    }
    final photo = ref.watch(_photoProvider(m.uuid)).value;
    final ada = photo != null && File(photo.path).existsSync();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: w.infoBg,
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
                  Text(t(context).slumpPhotoWaiting,
                      style: TextStyle(fontWeight: FontWeight.w700, color: w.infoFg)),
                  const SizedBox(height: 2),
                  Text(t(context).slumpPhotoWaitingBody(formatTime(m.at)),
                      style: TextStyle(fontSize: 12, color: w.muted)),
                ],
              ),
            ),
            TextButton(onPressed: onAmbil, child: Text(t(context).retakePhoto)),
            if (onBuang != null)
              IconButton(
                tooltip: t(context).discard,
                onPressed: onBuang,
                icon: Icon(Icons.close, size: 20, color: w.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// One photo of a TM — the delivery note or the slump test — with its label,
/// tappable to full screen.
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
    required this.takeSlumpPhoto,
    this.slumpPhotoUuid,
    this.slumpPhotoAt,
    required this.suppliers,
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
  final Future<String?> Function() takeSlumpPhoto;

  /// Foto slump yang sudah diambil sebelum TM ini masuk, berikut jamnya.
  /// Isian ini terbuka dengan foto tersebut sudah terpasang.
  final String? slumpPhotoUuid;
  final DateTime? slumpPhotoAt;

  /// Concrete suppliers to offer, and the previous TM's (or the header's)
  /// choice as the preselected default.
  final List<Map<String, Object?>> suppliers;
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
  late String? _slumpPhoto = widget.initial?['slumpPhotoUuid']?.toString() ?? widget.slumpPhotoUuid;
  String? _error;

  /// Chosen supplier id; [_other] = typed by hand, null = none.
  static const _other = -1;

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
      ((widget.supplierName ?? '').isNotEmpty && widget.suppliers.isNotEmpty ? _other : null);

  /// An unusual volume was shown once; the second tap saves it.
  bool _volumeConfirmed = false;

  @override
  void dispose() {
    for (final c in [_truck, _volume, _slump, _sounding, _supplier]) {
      c.dispose();
    }
    super.dispose();
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
    Navigator.pop(context, {
      'truckNo': orNull(_truck),
      // Picked from the list: id + its name. Typed: name only.
      'supplierID': picked == null ? null : toIntOrNull(picked['id']),
      'supplierName': picked == null ? orNull(_supplier) : '${picked['name']}',
      'volumeM3': decimalText(volume),
      'slumpCm': slump == null ? null : decimalText(slump, decimals: 1),
      'concreteDepthBeforeM': sounding == null ? null : decimalText(sounding),
      'ticketPhotoUuid': _photo,
      'slumpPhotoUuid': _slumpPhoto,
    });
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? t(context).editTruck(widget.seq) : t(context).truckArrived(widget.seq),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
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
            const SizedBox(height: 8),
            _PhotoField(
              uuid: _slumpPhoto,
              label: t(context).slumpTest,
              emptyLabel: t(context).photoSlump,
              note: widget.slumpPhotoAt == null || _slumpPhoto != widget.slumpPhotoUuid
                  ? null
                  : t(context).slumpPhotoWaitingBody(formatTime(widget.slumpPhotoAt!)),
              icon: Icons.science_outlined,
              onTake: () async {
                final f = await widget.takeSlumpPhoto();
                if (f != null) setState(() => _slumpPhoto = f);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _truck, decoration: InputDecoration(labelText: t(context).hullNoField)),
            const SizedBox(height: 12),
            if (widget.suppliers.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _supplierChoice,
                isExpanded: true,
                decoration: InputDecoration(labelText: t(context).truckSupplier),
                items: [
                  for (final s in widget.suppliers)
                    DropdownMenuItem<int?>(value: toIntOrNull(s['id']), child: Text('${s['name']}', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem<int?>(value: _other, child: Text(t(context).otherTypeName)),
                ],
                onChanged: (v) => setState(() => _supplierChoice = v),
              ),
              const SizedBox(height: 12),
            ],
            if ((widget.suppliers.isEmpty || _supplierChoice == _other)) ...[
              TextField(
                controller: _supplier,
                decoration: InputDecoration(
                  labelText: widget.suppliers.isEmpty ? t(context).truckSupplier : t(context).otherSupplierName,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _volume,
                  keyboardType: numeric,
                  inputFormatters: decimalInput(maxIntDigits: 2),
                  decoration: InputDecoration(labelText: t(context).volumePouredHere, suffixText: 'm³'),
                  onChanged: (_) {
                    setState(() {
                      if (_volumeConfirmed) _volumeConfirmed = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slump,
                  keyboardType: numeric,
                  inputFormatters: decimalInput(maxIntDigits: 2, decimals: 1),
                  decoration: InputDecoration(labelText: t(context).slumpField, suffixText: 'cm'),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(t(context).volumeSharedHint,
                  style: TextStyle(color: context.colors.muted, fontSize: 12.5, height: 1.35)),
            ),
            ?_overuseBanner(),
            const SizedBox(height: 12),
            TextField(
              controller: _sounding,
              keyboardType: numeric,
              inputFormatters: decimalInput(maxIntDigits: 3),
              decoration: InputDecoration(
                labelText: t(context).soundingBeforeOptional,
                suffixText: 'm',
                hintText: t(context).estimateHint(widget.estimatedConcreteBefore.toStringAsFixed(2).replaceAll('.', ',')),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: Dimens.minTouch + 4,
              child: FilledButton(onPressed: _submit,
                  child: Text(_editing ? t(context).saveChanges : t(context).saveTruck)),
            ),
          ],
        ),
      ),
    );
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

/// Casting data: grade, supplier, tremie bottom gap, note.
class _HeaderSheet extends StatefulWidget {
  const _HeaderSheet({
    required this.grade,
    required this.defaultGrade,
    required this.suppliers,
    required this.suppliersNarrowed,
    required this.supplierId,
    required this.supplier,
    required this.bottomDepthM,
    required this.tremieDepthStartM,
    required this.note,
  });

  /// [suppliers] holds only those with a PO in this project.
  final bool suppliersNarrowed;

  final double? grade;
  final double? defaultGrade;

  /// Concrete suppliers from the ERP: `{id, name}`. Empty = type the name.
  final List<Map<String, Object?>> suppliers;
  final int? supplierId;
  final String? supplier;

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
  late final _supplier = TextEditingController(text: widget.supplier ?? '');
  late final _gap = TextEditingController(
      text: widget.tremieDepthStartM == null ? '' : _decimal(widget.tremieDepthStartM));
  late final _note = TextEditingController(text: widget.note ?? '');
  String? _error;

  /// Chosen supplier id; [_other] = not on the list, typed by hand.
  static const _other = -1;
  late int? _supplierChoice = widget.supplierId ??
      (widget.supplier != null && widget.supplier!.isNotEmpty && widget.suppliers.isNotEmpty ? _other : null);

  @override
  void dispose() {
    for (final c in [_grade, _supplier, _gap, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final grade = _grade.text.trim().isEmpty ? null : parseNumber(_grade.text);
    if (_grade.text.trim().isNotEmpty && (grade == null || grade <= 0 || grade > 150)) {
      setState(() => _error = "Mutu fc' tidak masuk akal.");
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
    if (gap < -0.005 || gap > 1.005) {
      setState(() => _error = t(context).tremieDepthInvalid(formatMeters(widget.bottomDepthM)));
      return;
    }
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final picked = widget.suppliers.where((s) => toIntOrNull(s['id']) == _supplierChoice).firstOrNull;
    Navigator.pop(context, {
      'concreteGrade': grade == null ? null : decimalText(grade, decimals: 1),
      // Picked from the list: id + its name. Typed: name only.
      'supplierID': picked == null ? null : toIntOrNull(picked['id']),
      'supplierName': picked == null ? orNull(_supplier) : '${picked['name']}',
      'tremieDepthStartM': decimalText(dalam),
      // Celahnya ikut dikirim: server lama tidak mengenal kolom terukurnya,
      // dan hitungannya mundur ke sini.
      'tremieBottomGapM': decimalText(gap < 0 ? 0 : gap),
      'note': orNull(_note),
    });
  }

  @override
  Widget build(BuildContext context) {
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
            if (widget.suppliers.isNotEmpty) ...[
              TerraBanner(
                kind: BannerKind.info,
                title: widget.suppliersNarrowed ? t(context).suppliersWithPo : t(context).noPoYet,
                body: widget.suppliersNarrowed ? t(context).suppliersWithPoBody : t(context).noPoYetBody,
              ),
              DropdownButtonFormField<int?>(
                initialValue: _supplierChoice,
                isExpanded: true,
                decoration: InputDecoration(labelText: t(context).defaultSupplier),
                items: [
                  for (final s in widget.suppliers)
                    DropdownMenuItem<int?>(value: toIntOrNull(s['id']), child: Text('${s['name']}', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem<int?>(value: _other, child: Text(t(context).otherTypeName)),
                ],
                onChanged: (v) => setState(() => _supplierChoice = v),
              ),
              if (_supplierChoice == _other) const SizedBox(height: 12),
            ],
            if (widget.suppliers.isEmpty || _supplierChoice == _other)
              TextField(
                controller: _supplier,
                decoration: InputDecoration(labelText: widget.suppliers.isEmpty ? t(context).concreteSupplier : t(context).otherSupplierName),
              ),
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
