import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final db = ref.read(dbProvider);
    final rows = await db.getDocument(widget.uuid);
    Map<String, Object?>? doc;
    String? pilePointUuid = widget.pilePointUuid;
    if (rows != null) {
      doc = (jsonDecode(rows.body) as Map).cast<String, Object?>();
      pilePointUuid = '${doc['pilePointUuid']}';
    }
    if (pilePointUuid == null) {
      setState(() => _error = 'Log cor tidak ditemukan di HP ini.');
      return;
    }
    final pilePoint = await db.getMaster('pile_point', pilePointUuid);
    if (pilePoint == null) {
      setState(() => _error = 'Titik bor tidak ada di HP ini. Tarik data terbaru saat ada sinyal.');
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
      setState(() => _error = 'Elevasi GS titik ${pilePoint['code']} belum diisi. '
          'Kembali ke daftar titik, pilih "Tandai sudah dibor", lalu isi GS-nya.');
      return;
    }

    // One point, one casting log: the server refuses a second one.
    final existing = pilePoint['castingUuid'];
    if (doc == null && existing != null && '$existing' != widget.uuid) {
      setState(() => _error = 'Titik ${pilePoint['code']} sudah punya log cor'
          '${pilePoint['castingByName'] == null ? '' : ' dari ${pilePoint['castingByName']}'}. '
          'Satu titik hanya boleh satu log cor.');
      return;
    }

    // A new log needs the drilled depth too (the hole bottom). The point list
    // disables "Mulai log cor" until then; this catches any other way in.
    if (doc == null && localDrillDepth == null && toDoubleOrNull(pilePoint['drilledDepthM']) == null) {
      setState(() => _error = 'Titik ${pilePoint['code']} belum ditandai sudah dibor. '
          'Kembali ke daftar titik, pilih "Tandai sudah dibor", lalu isi kedalamannya.');
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
        'tremieBottomGapM': '0.30',
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
      if (mounted) showSnack(context, 'Belum masuk akun — tidak ada yang tersimpan.', icon: Icons.error_outline);
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
      ? 'Log cor sudah diperiksa kantor — tidak dapat diubah lagi.'
      : 'Log cor ini dipegang ${_holderName ?? 'rekan'} — ubah dari HP pemegangnya.';

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
        title: 'Tremie kepanjangan',
        body: 'Dengan segmen ${_decimal(lengthM)} m ini, ujung atas tremie ${formatMeters(stickUp)} di atas GS '
            '(paling tinggi ${formatMeters(tremieStickUpMaxM)}, setinggi hopper). '
            'Lubang ini cukup ${formatMeters(k.requiredTremieM)} tremie. Periksa lagi segmen yang terpasang.',
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
      title: 'Tremie bottom',
      label: 'Panjang (m)',
      icon: Icons.change_history,
      suffix: 'm',
      maxValue: 12,
      hint: 'Ujung runcing yang dipasang paling bawah. Ukur panjangnya untuk cor ini.',
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
    if (saved && mounted) showSnack(context, 'Segmen teratas dihapus dari susunan.');
  }

  Future<void> _customSegment() async {
    final v = (await _askNumber(title: 'Panjang segmen', label: 'Panjang (m)', icon: Icons.straighten, suffix: 'm', maxValue: 12))?.$1;
    if (v != null) await _addSegment(v);
  }

  /// A stop the user cannot pass: one button, nothing to override.
  Future<void> _block({required IconData icon, required String title, required String body}) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(icon, size: 32, color: c.colors.badFg),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(body, style: TextStyle(color: c.colors.ink, height: 1.4)),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Mengerti'))],
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
        final text = 'Setelah segmen ${_decimal(seg.lengthM)} m ini dicabut, tremie tinggal tertanam '
            '${formatMeters(math.max(after, 0))} di beton (paling sedikit ${formatMeters(limits.minimumM)}). '
            'Beton baru bisa menembus muka beton dan bercampur lumpur.';
        if (snap.concreteMeasured) {
          await _block(icon: Icons.dangerous_outlined, title: 'Jangan dicabut dulu', body: text);
          return;
        }
        final goOn = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: Icon(Icons.warning_amber_rounded, size: 32, color: c.colors.warnFg),
            title: const Text('Tertanam terlalu pendek', textAlign: TextAlign.center),
            content: Text('$text\n\nMuka beton ini perkiraan. Sounding dulu kalau ragu.', style: TextStyle(color: c.colors.ink, height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Tetap centang', style: TextStyle(color: c.colors.badFg))),
              FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            ],
          ),
        );
        if (goOn != true) return;
      }
    }
    await _setRemoved(segmentUuid, seq);
    if (mounted) {
      showSnack(context, seq == null ? 'Cabut dibatalkan; segmen terpasang lagi.' : 'Segmen tercatat dicabut setelah TM #$seq.');
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
        takeTicketPhoto: _takeTicketPhoto,
        suppliers: offer.suppliers,
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
        'ticketNo': result['ticketNo'],
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
        'note': null,
      });
    });
    if (!saved) return;
    if (mounted) showSnack(context, 'TM #$seq tersimpan.', icon: Icons.local_shipping_outlined);
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
          title: const Text('Beton sudah sampai cut-off', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Muka beton ${formatMeters(level.depthM)} dari GS, cut-off ${formatMeters(k.geometry.cutOffDepthM)}'
                '${over > 0.005 ? ' (lebih ${formatMeters(over)})' : ''}. '
                'Biasanya cor titik ini sudah cukup.',
                style: TextStyle(color: w.ink, height: 1.4),
              ),
              if (!level.measured) ...[
                const SizedBox(height: 10),
                Text(
                  'Angka ini perkiraan dari volume. Sounding dulu untuk memastikan.',
                  style: TextStyle(color: w.warnFg, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'finish'), child: const Text('Selesai cor')),
            FilledButton(onPressed: () => Navigator.pop(c, 'add'), child: const Text('Tetap tambah TM')),
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

  Future<bool> _updateTruck(String truckUuid, void Function(Map<Object?, Object?> t) f) => _update((d) {
        for (final x in (d['trucks'] as List)) {
          final m = x as Map;
          if (m['uuid'] == truckUuid) f(m);
        }
      });

  Future<void> _startTruck(Map<String, Object?> truck) async {
    final k = _castingState;
    if ((toIntOrNull(truck['seq']) ?? 0) == 1 && k.tremieTooLong) {
      await _block(
        icon: Icons.height,
        title: 'Tremie kepanjangan',
        body: 'Terpasang ${formatMeters(k.installedLengthAfter(0))}, ujung atasnya ${formatMeters(k.tremieStickUpM)} di atas GS '
            '(paling tinggi ${formatMeters(tremieStickUpMaxM)}). Lubang ini cukup ${formatMeters(k.requiredTremieM)}. '
            'Hapus segmen yang berlebih dulu.',
      );
      return;
    }
    if ((toIntOrNull(truck['seq']) ?? 0) == 1 && !k.tremieReachesBottom) {
      await _block(
        icon: Icons.vertical_align_bottom,
        title: 'Tremie belum sampai dasar',
        body: 'Terpasang ${formatMeters(k.installedLengthAfter(0))}, perlu ${formatMeters(k.requiredTremieM)} '
            '(dasar lubang dikurangi celah). Tambah segmen dulu: beton yang jatuh dari atas akan bercampur lumpur.',
      );
      return;
    }
    await Notifications.cancelIdleReminders();
    final start = DateTime.now();
    if (!await _updateTruck('${truck['uuid']}', (t) => t['startAt'] = isoWithOffset(start))) return;
    await Notifications.requestPermission();
    await Notifications.showStopwatch(
      route: '/casting/log/${widget.uuid}',
      title: 'TM #${truck['seq']} dicor · ${_pilePoint!['code']}',
      body: '${_decimal(truck['volumeM3'])} m³ · ketuk untuk membuka log cor',
      start: start,
    );
    await _scheduleReminder(truck, poured: Duration.zero);
    if (mounted) showSnack(context, 'Cor TM #${truck['seq']} dimulai. Jamnya berjalan di notifikasi.');
  }

  /// Vibrating reminder when this TM has poured for [truckReminderAfter]
  /// (pauses not counted) and is still not finished.
  Future<void> _scheduleReminder(Map<String, Object?> truck, {required Duration poured}) {
    final left = truckReminderAfter - poured;
    return Notifications.scheduleTruckReminder(
      route: '/casting/log/${widget.uuid}',
      title: 'TM #${truck['seq']} sudah ${truckReminderAfter.inMinutes} menit · ${_pilePoint!['code']}',
      body: 'Belum selesai dicor. Cek muka beton dan posisi tremie.',
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
    if (reason == null) return;
    final now = DateTime.now();
    // A pause is not pouring time: the reminder is set again on Lanjut.
    await Notifications.cancelTruckReminder();
    await Notifications.schedulePauseReminders(
      route: '/casting/log/${widget.uuid}',
      title: 'TM #$seq masih dijeda · ${_pilePoint!['code']}',
      body: 'Sudah lanjut cor? Ketuk Lanjut di log cor',
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
      title: 'TM #$seq dijeda · ${_pilePoint!['code']}',
      body: '${pauseReasonLabel(reason)} · ketuk untuk melanjutkan',
    );
    if (mounted) showSnack(context, 'Cor dijeda: ${pauseReasonLabel(reason)}.', icon: Icons.pause_circle_outline);
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
    if (!await _update((d) => _closePause(d, seq, now))) return;
    await Notifications.cancelPauseReminders();
    // The notification clock cannot pause: restart it from a start moved
    // forward by the paused time, so it shows pouring time only.
    final poured = pouringTime(truck, _pauses, now) ?? Duration.zero;
    await Notifications.showStopwatch(
      route: '/casting/log/${widget.uuid}',
      title: 'TM #$seq dicor · ${_pilePoint!['code']}',
      body: '${_decimal(truck['volumeM3'])} m³ · ketuk untuk membuka log cor',
      start: now.subtract(poured),
    );
    await _scheduleReminder(truck, poured: poured);
    if (mounted) showSnack(context, 'Cor TM #$seq dilanjutkan.');
  }

  Future<void> _finishTruck(Map<String, Object?> truck) async {
    final end = DateTime.now();
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
      title: 'Belum ada TM berikutnya · ${_pilePoint!['code']}',
      body: 'Awas sambungan dingin. Cek kapan TM datang',
      from: end,
    );
    if (!mounted) return;
    showSnack(context, 'TM #$finishedSeq selesai dicor.');
    await _askSoundingAfter(truck);
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
      title: 'Sounding setelah TM #$seq',
      label: 'Kedalaman muka beton dari GS (m)',
      icon: Icons.local_shipping_outlined,
      suffix: 'm',
      maxValue: 200,
      initial: toDoubleOrNull(truck['concreteDepthAfterM']),
      hint: 'Wajib diukur. Perkiraan dari volume: ${formatMeters(k.concreteAfter(seq).depthM)}.',
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
                Expanded(child: Text('Sounding TM #$seq belum diisi. Wajib sebelum TM berikutnya.')),
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
      title: start ? 'Jam mulai TM #${truck['seq']}' : 'Jam selesai TM #${truck['seq']}',
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
      title: after ? 'Sounding setelah TM #${truck['seq']}' : 'Sounding sebelum TM #${truck['seq']}',
      label: 'Kedalaman muka beton dari GS (m)',
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
            ? 'Sounding TM #${truck['seq']} dikosongkan.'
            : 'Sounding TM #${truck['seq']} tersimpan: ${formatMeters(value)}.',
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
        gap: toDoubleOrNull(_doc!['tremieBottomGapM']) ?? 0.30,
        note: _doc!['note']?.toString(),
      ),
    );
    if (result == null) return;
    if (!await _update((d) => d.addAll(result))) return;
    if (mounted) showSnack(context, 'Data cor disimpan.');
  }

  Future<void> _finishCasting() async {
    final unsounded = _unsoundedTruck;
    if (unsounded != null && !await _askSoundingAfter(unsounded)) return;
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
        showSnack(context, 'Status selesai belum tersimpan. Coba tekan "Selesai cor" sekali lagi.', icon: Icons.error_outline);
      }
      return;
    }
    if (!mounted) return;
    await _remindCleaning();
    if (mounted) showSnack(context, 'Cor ${_pilePoint!['code']} selesai. Terkirim otomatis saat ada sinyal.');
  }

  Future<void> _reopenCasting() async {
    if (!await _update((d) => d['status'] = 'berjalan')) return;
    if (mounted) showSnack(context, 'Log cor dibuka lagi. Jangan lupa Selesai cor setelah beres.', icon: Icons.lock_open_outlined);
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
            title: const Text('Bersihkan tremie & hopper', textAlign: TextAlign.center),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TerraBanner(
                    kind: BannerKind.warning,
                    title: 'Sebelum dipakai lagi',
                    body: 'Sisa beton yang mengeras di dalam pipa atau sambungan bisa menyumbat tremie '
                        'saat cor berikutnya.',
                  ),
                  step(Icons.water_drop_outlined, 'Siram/semprot hopper dan tiap segmen tremie sampai bersih dari sisa beton.'),
                  step(Icons.link, 'Bersihkan sambungan dan karet seal; ganti seal yang rusak.'),
                  step(Icons.schedule, 'Lakukan segera, sebelum sisa beton mengeras.'),
                  step(Icons.inventory_2_outlined, 'Susun kembali di tempatnya, jangan tergeletak di tanah.'),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Siap, dibersihkan')),
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
      return Scaffold(appBar: AppBar(title: const Text('Log cor')), body: ErrorState(title: _error!));
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
        title: Text('Cor ${_pilePoint!['code']}'),
        actions: [
          if (_row != null && !_finished && !_readOnly)
            IconButton(
              tooltip: 'Oper ke rekan',
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
          if (_handedAway)
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.swap_horiz,
              title: 'Dioper ke ${_holderName ?? 'rekan'}',
              body: 'Log cor ini dilanjutkan dari HP ${_holderName ?? 'rekan'}. '
                  'Di HP ini hanya bisa dilihat; perubahan dibuat di HP pemegangnya.',
            ),
          if (_row?.sendStatus == 'rejected' && !_handedAway)
            TerraBanner(kind: BannerKind.danger, title: 'Ditolak server', body: reasonText(_row!.reason, _row!.detail)),
          if (_locked)
            TerraBanner(
              kind: BannerKind.ok,
              title: 'Sudah diperiksa kantor',
              body: [if (_row!.serverNote != null) 'Catatan: ${_row!.serverNote}', 'Log cor ini tidak dapat diubah lagi.'].join('\n'),
            ),
          if (_grade == null)
            TerraBanner(
              kind: BannerKind.warning,
              title: "Mutu beton (fc') belum diisi",
              body: 'Titik dan proyek ini belum punya mutu bawaan. Isi di data cor, atau log cor akan ditolak server.',
              action: TextButton(onPressed: _editHeader, child: const Text('Isi')),
            ),
          if (g.drilledDepthM == null)
            const TerraBanner(
              kind: BannerKind.info,
              title: 'Kedalaman bor belum ditandai',
              body: 'Hitungan memakai panjang bor RENCANA. Tandai kedalaman aktual dari daftar titik supaya saran potong tepat.',
            ),

          _SummaryCard(geometry: g, castingState: k, grade: _grade, supplier: _doc!['supplierName']?.toString(), onEdit: _readOnly ? null : _editHeader),
          if (_row?.serverStatus != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: ReviewBadge(status: _row!.serverStatus!)),

          // --- live cross-section -------------------------------------------
          if (_tremie.isNotEmpty) _sectionView(k),
          ?_overuseBanner(k),

          // --- tremie -----------------------------------------------------
          _SectionTitle('Tremie', 'Segmen bawah → atas. Ujung bawah ${formatMeters(k.bottomGapM)} di atas dasar lubang.'),
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
          _SectionTitle('Truk mixer (TM)', '${_trucks.length} TM · ${_decimal(k.totalVolumeM3)} m³'),
          for (final truck in _trucks..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0)))
            _TruckCard(
              truck: truck,
              castingState: k,
              locked: _readOnly,
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
                        Text('Belum ada TM', style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                        const SizedBox(height: 2),
                        Text(
                          _readOnly
                              ? 'Log cor ini tidak punya TM.'
                              : _tremie.isEmpty
                                  ? 'Susun tremie dulu, lalu tekan "TM #1 datang" saat truk pertama tiba.'
                                  : 'Tekan "TM #1 datang" di bawah saat truk pertama tiba.',
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
                        child: OutlinedButton(onPressed: _finishCasting, child: const Text('Selesai cor')),
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
                                  label: const Text('Jeda'),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _resumeTruck(running),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Lanjut'),
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
                                  label: Text('Selesai TM #${running['seq']}'),
                                )
                              : lastTruck != null && lastTruck['startAt'] == null
                                  ? FilledButton.icon(
                                      onPressed: () => _startTruck(lastTruck),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text('Mulai cor TM #${lastTruck['seq']}'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: _tremie.isEmpty ? null : _newTruck,
                                      icon: const Icon(Icons.local_shipping_outlined),
                                      label: Text(_tremie.isEmpty ? 'Susun tremie dulu' : 'TM #${seq + 1} datang'),
                                    ),
                        ),
                      ),
                    if (_finished)
                      Expanded(
                        child: TerraBanner(
                          kind: BannerKind.ok,
                          title: 'Cor selesai',
                          body: _isNew ? null : 'Tersimpan. Dikirim otomatis.',
                          action: TextButton(onPressed: _reopenCasting, child: const Text('Buka lagi')),
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
      title: 'Beton terpakai ${over.toStringAsFixed(0)}% di atas teoretis',
      body: 'Sampai muka beton ${formatMeters(level)}: terpakai ${_decimal(used)} m³, '
          'teoretis ${_decimal(k.geometry.areaM2 * (k.geometry.bottomDepthM - level))} m³. '
          'Kemungkinan lubang membesar atau runtuh. Laporkan ke pengawas.',
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
        title: r.cuts.isEmpty ? 'Rencana TM #$seq: tidak perlu cabut' : 'Rencana TM #$seq',
        body: [
          for (final p in r.cuts)
            '• Setelah ±${_decimal(p.afterM3)} m³: cabut ${p.toRemove.map((s) => '#${position[s.key]} (${_decimal(s.lengthM)} m)').join(' lalu ')} '
                '→ tertanam ${_decimal(p.embedmentBeforeM)} → ${_decimal(p.embedmentAfterM)} m',
          for (final p in r.warnings)
            p.kind == WarningKind.embedmentTooShort
                ? '⚠ Tertanam sebelum TM ini hanya ${_decimal(p.embedmentM)} m — periksa sounding.'
                : '⚠ Setelah ±${_decimal(p.afterM3)} m³ tertanam melewati 6 m dan tidak ada segmen yang aman dicabut.',
          'Perkiraan akhir TM: muka beton ${formatMeters(r.finalConcreteDepthM)}, tertanam ${formatMeters(r.finalEmbedmentM)}'
              '${r.cutOffReached ? ' — cut-off tercapai' : ''}.',
          if (k.averageRatio != 1.0) 'Memakai rasio overbreak ${_decimal(k.averageRatio)} dari sounding TM sebelumnya.',
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
      title: 'Tertanam ${formatMeters(embedment)}${concreteAt.measured ? '' : ' (perkiraan)'}',
      body: [
        if (!concreteAt.measured) 'Muka beton belum disounding — angka ini dari volume. Sounding dulu sebelum mencabut.',
        if (suggestion.isEmpty)
          embedment < limits.minimumM
              ? 'Kurang dari 1 m: JANGAN cabut. Tremie berisiko keluar dari beton.'
              : 'Tidak perlu cabut sekarang.'
        else
          'Saran: cabut ${suggestion.map((s) => '#${position[s.key]} (${_decimal(s.lengthM)} m)').join(', ')} '
              '→ tertanam ${formatMeters(embedment - suggestion.fold(0.0, (a, s) => a + s.lengthM))}. Centang di daftar tremie setelah dicabut.',
      ].join('\n'),
      action: suggestion.isEmpty
          ? null
          : TextButton(
              onPressed: () async {
                for (final s in suggestion) {
                  await _toggleRemoved(s.key, seq);
                }
              },
              child: const Text('Centang'),
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
            cell('Diameter', 'D${geometry.diameterMm}'),
            cell("Mutu fc'", grade == null ? '–' : '${_decimal(grade, d: 1)} MPa', colors: grade == null ? w.warnFg : null),
            cell('Pemasok', supplier ?? '–'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell('Dasar lubang', formatMeters(geometry.bottomDepthM)),
            cell('Cut-off', formatMeters(geometry.cutOffDepthM)),
            cell('Muka beton', '${formatMeters(concreteAt.depthM)}${concreteAt.measured || seq == 0 ? '' : '*'}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell('Teoritis', '${_decimal(theoretical)} m³'),
            cell('Terpakai', '${_decimal(castingState.totalVolumeM3)} m³'),
            cell('Lebih pakai', overuse == null ? '–' : '${overuse >= 0 ? '+' : ''}${_decimal(overuse, d: 1)}%'),
          ]),
          if (seq > 0 && !concreteAt.measured) ...[
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text('* perkiraan dari volume', style: TextStyle(color: w.faint, fontSize: 12))),
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
            ? ('Perlu ${formatMeters(requiredLength)}. Mulai dari tremie bottom (ujung runcing).', w.muted, Icons.straighten)
            : k.tremieTooLong
                ? (
                    'Kepanjangan: ujung atas ${formatMeters(stickUp)} di atas GS (paling tinggi '
                        '${formatMeters(tremieStickUpMaxM)}). Hapus segmen teratas.',
                    w.badFg,
                    Icons.error_outline,
                  )
                : k.tremieReachesBottom
                    ? (
                        'Sudah sampai dasar. Ujung atas ${formatMeters(math.max(stickUp, 0))} di atas GS (hopper).',
                        w.okFg,
                        Icons.check_circle_outline,
                      )
                    : ('Kurang ${formatMeters(requiredLength - total)} lagi sampai dasar.', w.warnFg, Icons.warning_amber_rounded);

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
                child: Text('dari ${formatMeters(requiredLength)} perlu', style: TextStyle(color: w.muted, fontSize: 13)),
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
                label: const Text('Pasang tremie bottom'),
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
                ActionChip(label: const Text('Lainnya'), onPressed: onCustom),
                ActionChip(avatar: const Icon(Icons.remove, size: 16), label: const Text('Hapus teratas'), onPressed: onRemoveTop),
              ],
            ),
          ],
          if (k.segments.isNotEmpty) const Divider(height: 24),
          // Listed from the TOP, like the tremie in the hole drawn above.
          if (canRemove && k.segments.isNotEmpty)
            const TerraBanner(
              kind: BannerKind.info,
              title: 'Cabut tremie',
              body: 'Tekan "Cabut" pada segmen yang dicabut setelah TM ini. Gambar di atas ikut berubah.',
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
                title: s.isBottom ? 'Tremie bottom · ${_decimal(s.lengthM)} m' : 'Pipa ${_decimal(s.lengthM)} m',
                subtitle: removed
                    ? 'Dicabut setelah TM #${s.removedAfterTruck}'
                    : [
                        if (at != null) _hangText(at.top, at.bottom),
                        if (lowest) 'paling bawah',
                      ].join(' · '),
                onTap: canCheck ? toggle : null,
                trailing: !canCheck
                    ? null
                    : removed
                        ? TextButton.icon(onPressed: toggle, icon: const Icon(Icons.undo, size: 18), label: const Text('Batal'))
                        : OutlinedButton.icon(
                            onPressed: toggle,
                            icon: const Icon(Icons.north, size: 18),
                            label: const Text('Cabut'),
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

    Widget value(String label, String body, {VoidCallback? onTap, bool edited = false}) => InkWell(
          onTap: locked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(label, style: TextStyle(color: w.muted, fontSize: 13))),
                Text(body, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
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
              Expanded(
                child: Text('TM #$seq · ${_decimal(truck['volumeM3'])} m³',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
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
              if (truck['truckNo'] != null) 'Lambung ${truck['truckNo']}',
              if (truck['ticketNo'] != null) 'SJ ${truck['ticketNo']}',
              if (truck['supplierName'] != null) '${truck['supplierName']}',
              if (truck['slumpCm'] != null) 'Slump ${_decimal(truck['slumpCm'], d: 1)} cm',
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          value('Tremie terpasang', '${_decimal(truck['tremieLengthM'])} m'),
          value('Mulai', start == null ? '–' : formatTime(start), onTap: start == null ? null : onEditStart, edited: truck['startEdited'] == true),
          value('Selesai', end == null ? '–' : formatTime(end), onTap: end == null ? null : onEditEnd, edited: truck['endEdited'] == true),
          if (pauses.isNotEmpty) ...[
            value('Jeda', '${pauses.length}× · ${formatDuration(pausedTotal)}'),
            for (final p in pauses)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  '${pauseReasonLabel(p['reason'])} · ${_clock(p['startAt'])}–${p['endAt'] == null ? 'sekarang' : _clock(p['endAt'])}',
                  style: TextStyle(color: w.muted, fontSize: 13),
                ),
              ),
          ],
          value('Sounding sebelum', truck['concreteDepthBeforeM'] == null ? '–' : formatMeters(toDoubleOrNull(truck['concreteDepthBeforeM'])),
              onTap: onSoundingBefore),
          value('Sounding sesudah', truck['concreteDepthAfterM'] == null ? '–' : formatMeters(toDoubleOrNull(truck['concreteDepthAfterM'])),
              onTap: end == null ? null : onSoundingAfter),
          if (end != null && truck['concreteDepthAfterM'] == null && !locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: w.badFg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Sounding sesudah wajib diisi. Ketuk baris di atas.',
                        style: TextStyle(color: w.badFg, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
          if (ratio != null) value('Rasio overbreak', _decimal(ratio)),
          if (truck['ticketPhotoUuid'] != null) _TicketPhoto(uuid: '${truck['ticketPhotoUuid']}'),
        ],
      ),
    );
  }
}

class _TicketPhoto extends ConsumerWidget {
  const _TicketPhoto({required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(_photoProvider(uuid)).value;
    if (photo == null || !File(photo.path).existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(File(photo.path)))),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(photo.path), height: 90, fit: BoxFit.cover, cacheHeight: 270),
        ),
      ),
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
        ? (w.surface2, w.muted, 'Dijeda')
        : over
            ? (w.badBg, w.badFg, 'Lewat ${truckReminderAfter.inMinutes} menit')
            : (w.brandSoft, w.brandStrong, 'Waktu tuang');
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
            Text('Jeda TM #$seq', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
            const SizedBox(height: 4),
            Text('Kenapa dijeda? Jam tuang berhenti, dan HP bergetar tiap 3 menit sampai Anda ketuk Lanjut.', style: TextStyle(color: w.muted)),
            const SizedBox(height: 14),
            for (final e in pauseReasons.entries) ...[
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
class _TruckSheet extends StatefulWidget {
  const _TruckSheet({
    required this.seq,
    required this.estimatedConcreteBefore,
    required this.takeTicketPhoto,
    required this.suppliers,
    required this.supplierId,
    required this.supplierName,
  });

  final int seq;
  final double estimatedConcreteBefore;
  final Future<String?> Function() takeTicketPhoto;

  /// Concrete suppliers to offer, and the previous TM's (or the header's)
  /// choice as the preselected default.
  final List<Map<String, Object?>> suppliers;
  final int? supplierId;
  final String? supplierName;

  @override
  State<_TruckSheet> createState() => _TruckSheetState();
}

class _TruckSheetState extends State<_TruckSheet> {
  final _truck = TextEditingController();
  final _ticket = TextEditingController();
  final _volume = TextEditingController();
  final _slump = TextEditingController();
  final _sounding = TextEditingController();
  late final _supplier = TextEditingController(text: widget.supplierName ?? '');
  String? _photo;
  String? _error;

  /// Chosen supplier id; [_other] = typed by hand, null = none.
  static const _other = -1;
  late int? _supplierChoice = widget.supplierId ??
      ((widget.supplierName ?? '').isNotEmpty && widget.suppliers.isNotEmpty ? _other : null);

  /// An unusual volume was shown once; the second tap saves it.
  bool _volumeConfirmed = false;

  @override
  void dispose() {
    for (final c in [_truck, _ticket, _volume, _slump, _sounding, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final volume = parseNumber(_volume.text);
    if (volume == null || volume <= 0 || volume > truckVolumeMaxM3) {
      setState(() => _error = 'Isi volume TM (m³), paling besar ${decimalText(truckVolumeMaxM3, decimals: 0)}.');
      return;
    }
    if (volume > truckVolumeUsualMaxM3 && !_volumeConfirmed) {
      setState(() {
        _volumeConfirmed = true;
        _error = '${_decimal(volume)} m³ lebih besar dari biasanya (5–7 m³). Cek surat jalannya; kalau benar, tekan Simpan TM sekali lagi.';
      });
      return;
    }
    final slump = _slump.text.trim().isEmpty ? null : parseNumber(_slump.text);
    if (_slump.text.trim().isNotEmpty && (slump == null || slump < 0 || slump > 40)) {
      setState(() => _error = 'Slump tidak masuk akal (0–40 cm).');
      return;
    }
    final sounding = _sounding.text.trim().isEmpty ? null : parseNumber(_sounding.text);
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final picked = widget.suppliers.where((s) => toIntOrNull(s['id']) == _supplierChoice).firstOrNull;
    Navigator.pop(context, {
      'truckNo': orNull(_truck),
      'ticketNo': orNull(_ticket),
      // Picked from the list: id + its name. Typed: name only.
      'supplierID': picked == null ? null : toIntOrNull(picked['id']),
      'supplierName': picked == null ? orNull(_supplier) : '${picked['name']}',
      'volumeM3': decimalText(volume),
      'slumpCm': slump == null ? null : decimalText(slump, decimals: 1),
      'concreteDepthBeforeM': sounding == null ? null : decimalText(sounding),
      'ticketPhotoUuid': _photo,
    });
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, MediaQuery.viewInsetsOf(context).bottom + Dimens.pagePadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TM #${widget.seq} datang', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await widget.takeTicketPhoto();
                if (f != null) setState(() => _photo = f);
              },
              icon: Icon(_photo == null ? Icons.receipt_long_outlined : Icons.check_circle),
              label: Text(_photo == null ? 'Foto surat jalan TM' : 'Foto surat jalan tersimpan · ulang'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _truck, decoration: const InputDecoration(labelText: 'Nomor lambung TM'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _ticket, decoration: const InputDecoration(labelText: 'Nomor surat jalan'))),
            ]),
            const SizedBox(height: 12),
            if (widget.suppliers.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _supplierChoice,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pemasok beton TM ini'),
                items: [
                  for (final s in widget.suppliers)
                    DropdownMenuItem<int?>(value: toIntOrNull(s['id']), child: Text('${s['name']}', overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem<int?>(value: _other, child: Text('Lainnya — ketik nama')),
                ],
                onChanged: (v) => setState(() => _supplierChoice = v),
              ),
              const SizedBox(height: 12),
            ],
            if ((widget.suppliers.isEmpty || _supplierChoice == _other)) ...[
              TextField(
                controller: _supplier,
                decoration: InputDecoration(
                  labelText: widget.suppliers.isEmpty ? 'Pemasok beton TM ini' : 'Nama pemasok lain',
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
                  decoration: const InputDecoration(labelText: 'Volume', suffixText: 'm³'),
                  onChanged: (_) {
                    if (_volumeConfirmed) setState(() => _volumeConfirmed = false);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slump,
                  keyboardType: numeric,
                  inputFormatters: decimalInput(maxIntDigits: 2, decimals: 1),
                  decoration: const InputDecoration(labelText: 'Slump', suffixText: 'cm'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _sounding,
              keyboardType: numeric,
              inputFormatters: decimalInput(maxIntDigits: 3),
              decoration: InputDecoration(
                labelText: 'Sounding sebelum (opsional)',
                suffixText: 'm',
                hintText: 'perkiraan ${widget.estimatedConcreteBefore.toStringAsFixed(2).replaceAll('.', ',')}',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: Dimens.minTouch + 4,
              child: FilledButton(onPressed: _submit, child: const Text('Simpan TM')),
            ),
          ],
        ),
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
    required this.gap,
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
  final double gap;
  final String? note;

  @override
  State<_HeaderSheet> createState() => _HeaderSheetState();
}

class _HeaderSheetState extends State<_HeaderSheet> {
  late final _grade = TextEditingController(text: widget.grade == null ? '' : _decimal(widget.grade, d: 1));
  late final _supplier = TextEditingController(text: widget.supplier ?? '');
  late final _gap = TextEditingController(text: _decimal(widget.gap));
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
    final gap = parseNumber(_gap.text);
    if (gap == null || gap < 0 || gap > 5) {
      setState(() => _error = 'Celah bawah tremie 0–5 m.');
      return;
    }
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final picked = widget.suppliers.where((s) => toIntOrNull(s['id']) == _supplierChoice).firstOrNull;
    Navigator.pop(context, {
      'concreteGrade': grade == null ? null : decimalText(grade, decimals: 1),
      // Picked from the list: id + its name. Typed: name only.
      'supplierID': picked == null ? null : toIntOrNull(picked['id']),
      'supplierName': picked == null ? orNull(_supplier) : '${picked['name']}',
      'tremieBottomGapM': decimalText(gap),
      'note': orNull(_note),
    });
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, MediaQuery.viewInsetsOf(context).bottom + Dimens.pagePadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Data cor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_error != null) TerraBanner(kind: BannerKind.danger, title: _error!),
            if (widget.defaultGrade != null)
              TerraBanner(
                kind: BannerKind.info,
                title: "Mutu bawaan fc' ${_decimal(widget.defaultGrade, d: 1)} MPa",
                body: 'Dari titik/proyek. Isi hanya bila beton yang datang berbeda.',
              ),
            TextField(controller: _grade, keyboardType: numeric, inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1), decoration: const InputDecoration(labelText: "Mutu fc'", suffixText: 'MPa')),
            const SizedBox(height: 12),
            if (widget.suppliers.isNotEmpty) ...[
              TerraBanner(
                kind: BannerKind.info,
                title: widget.suppliersNarrowed
                    ? 'Pemasok dengan PO beton di proyek ini'
                    : 'Belum ada PO beton di proyek ini',
                body: widget.suppliersNarrowed
                    ? 'Jadi isian awal tiap TM; tiap TM datang masih bisa memilih pemasoknya sendiri. '
                        'Tidak ada di daftar? Pilih "Lainnya" lalu ketik namanya, dan kabari kantor.'
                    : 'Menampilkan semua pemasok beton; daftar menyempit sendiri setelah kantor membuat PO. '
                        'Tiap TM datang masih bisa memilih pemasoknya sendiri.',
              ),
              DropdownButtonFormField<int?>(
                initialValue: _supplierChoice,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pemasok beton bawaan (batching plant)'),
                items: [
                  for (final s in widget.suppliers)
                    DropdownMenuItem<int?>(value: toIntOrNull(s['id']), child: Text('${s['name']}', overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem<int?>(value: _other, child: Text('Lainnya — ketik nama')),
                ],
                onChanged: (v) => setState(() => _supplierChoice = v),
              ),
              if (_supplierChoice == _other) const SizedBox(height: 12),
            ],
            if (widget.suppliers.isEmpty || _supplierChoice == _other)
              TextField(
                controller: _supplier,
                decoration: InputDecoration(labelText: widget.suppliers.isEmpty ? 'Pemasok beton (batching plant)' : 'Nama pemasok lain'),
              ),
            const SizedBox(height: 12),
            TextField(controller: _gap, keyboardType: numeric, inputFormatters: decimalInput(maxIntDigits: 1), decoration: const InputDecoration(labelText: 'Celah ujung tremie di atas dasar', suffixText: 'm')),
            const SizedBox(height: 12),
            TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan')),
            const SizedBox(height: 18),
            SizedBox(height: Dimens.minTouch + 4, child: FilledButton(onPressed: _submit, child: const Text('Simpan'))),
          ],
        ),
      ),
    );
  }
}

/// "kedalaman 3,00–6,00 m", or with the part above ground spelled out.
String _hangText(double top, double bottom) {
  String m(double v) => v.abs().toStringAsFixed(2).replaceAll('.', ',');
  if (bottom <= 0) return '${m(top)}–${m(bottom)}\u00A0m di atas GS';
  if (top < 0) return '${m(top)}\u00A0m di atas GS sampai kedalaman ${m(bottom)}\u00A0m';
  return 'kedalaman ${m(top)}–${m(bottom)}\u00A0m';
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
  static const _reasons = <(String, String, IconData)>[
    ('tremie_tersumbat', 'Tremie tersumbat / beton macet', Icons.block),
    ('tm_tidak_datang', 'TM tidak datang / beton habis', Icons.local_shipping_outlined),
    ('lubang_runtuh', 'Lubang runtuh', Icons.terrain_outlined),
    ('alat_cuaca', 'Alat rusak atau cuaca', Icons.bolt_outlined),
    ('lainnya', 'Lainnya', Icons.edit_outlined),
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
    final label = _reasons.firstWhere((r) => r.$1 == _reason).$2;
    final detail = _detail.text.trim();
    final why = _reason == 'lainnya' ? detail : (detail.isEmpty ? label : '$label — $detail');
    return 'Cor dihentikan sebelum cut-off '
        '(kurang ${formatMeters(widget.missingM)} ≈ ${_decimal(_short.volumeM3)} m³): $why';
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
      title: Text(widget.short ? 'Beton belum sampai cut-off' : 'Selesai cor ${widget.code}?',
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
                title: 'Masih kurang ${_decimal(_short.volumeM3)} m³ (±${_short.trucks} TM lagi)',
                body: [
                  'Muka beton ${formatMeters(widget.levelDepthM)} dari GS, cut-off '
                      '${formatMeters(widget.cutOffDepthM)} — kurang ${formatMeters(widget.missingM)}.',
                  'Sudah tercor ${_decimal(widget.pouredM3)} m³ dari ±${_decimal(widget.theoreticalM3)} m³ teoritis'
                      '${percent == null ? '' : ' (${percent.toStringAsFixed(0)}%)'}.',
                  if (!widget.measured) 'Angka ini perkiraan dari volume — sounding dulu untuk memastikan.',
                ].join('\n'),
              ),
              const SizedBox(height: 12),
            ],
            if (_mustExplain) ...[
              Text('Tiang yang ditutup di bawah cut-off jadi tiang pendek, dan beton mengeras — '
                  'tidak bisa dibatalkan. Kalau cor memang dihentikan, pilih alasannya; kantor perlu tahu. '
                  'Kalau cuma salah tekan, pilih "Belum — lanjut cor".',
                  style: TextStyle(color: w.ink, height: 1.4)),
              const SizedBox(height: 12),
              for (final (code, label, icon) in _reasons) _reasonRow(code, label, icon),
              if (_reason != null)
                TextField(
                  controller: _detail,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _reason == 'lainnya' ? 'Alasan (wajib)' : 'Keterangan (boleh kosong)',
                    hintText: 'mis. tremie mampet di segmen ke-3, beton sudah mengeras',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ] else
              Text(
                widget.short
                    ? 'Kurang sedikit saja dari cut-off — kelebihan di atas cut-off memang dipotong nanti. '
                        'Titik ditandai sudah dicor; log cor masih dapat diperbaiki sampai diperiksa kantor.'
                    : 'Titik ditandai sudah dicor. Log cor masih dapat diperbaiki sampai diperiksa kantor.',
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
                child: Text('Tetap selesai', style: TextStyle(color: _canFinish ? w.badFg : w.faint)),
              ),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Belum — lanjut cor')),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Belum')),
              FilledButton(
                onPressed: () => Navigator.pop(context, const _FinishResult()),
                child: Text(widget.short ? 'Tetap selesai' : 'Selesai'),
              ),
            ],
    );
  }
}
