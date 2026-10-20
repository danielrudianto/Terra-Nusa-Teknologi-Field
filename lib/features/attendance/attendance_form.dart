import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/device/device_timestamp.dart';
import '../../core/device/camera.dart';
import '../../core/device/location.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/reasons.dart';
import '../../core/util/format.dart';
import '../../core/util/distance.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/view_states.dart';
import 'attendance_stamp.dart';
import '../../core/i18n.dart';

/// Crew attendance for one project, one day.
///
/// DOCUMENT BODY = EXACTLY THE SERVER'S `DataAbsen`
///
///   projectID, date, checkIn{...}, checkOut{...}, lines[{uuid, workerUuid,
///   status, overtimeHours}]
///
/// No other fields — the server rejects fields it does not recognize.
///
/// SAVED EVERY TIME
///
/// Check-in/check-out is saved as soon as the photo is taken: a phone that
/// dies from a flat battery in the middle of the day must not lose the next
/// morning's attendance. Crew ticks are saved with the Save button.
class AttendanceForm extends ConsumerStatefulWidget {
  const AttendanceForm({super.key, required this.uuid, this.projectId});

  final String? uuid;
  final int? projectId;

  @override
  ConsumerState<AttendanceForm> createState() => _AttendanceFormState();
}

class _Line {
  _Line({required this.uuid, this.status = 'hadir', this.overtime = 0});

  final String uuid;
  String status;
  double overtime;
}

class _AttendanceFormState extends ConsumerState<AttendanceForm> {
  late final String _uuid = widget.uuid ?? newUuid();
  int? _projectId;
  String _date = isoDate(DateTime.now());
  Map<String, Object?>? _checkIn;
  Map<String, Object?>? _checkOut;
  final Map<String, _Line> _lines = {};
  DocumentRow? _doc;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String _crewSearch = '';

  /// "Pekerja lain" (workers of other projects) opened by the user.
  bool _showOthers = false;
  String? _locationProblem;

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _load();
  }

  Future<void> _load() async {
    // A new attendance starts on the user's own project.
    if (widget.uuid == null && _projectId == null) {
      _projectId = await ref.read(myProjectProvider.future);
    }
    if (widget.uuid != null) {
      final d = await ref.read(dbProvider).getDocument(_uuid);
      if (d != null) _fillFrom(d);
    } else if (_projectId != null && await _openExisting(_projectId!)) {
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fillFrom(DocumentRow d) {
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    _doc = d;
    _projectId = toIntOrNull(body['projectID']);
    _date = '${body['date']}';
    _checkIn = (body['checkIn'] as Map?)?.cast<String, Object?>();
    _checkOut = (body['checkOut'] as Map?)?.cast<String, Object?>();
    _lines.clear();
    for (final b in (body['lines'] as List?) ?? const []) {
      final m = (b as Map).cast<String, Object?>();
      _lines['${m['workerUuid']}'] = _Line(
        uuid: '${m['uuid']}',
        status: '${m['status'] ?? 'hadir'}',
        overtime: toDoubleOrNull(m['overtimeHours']) ?? 0,
      );
    }
  }

  /// Locked once the office has reviewed it (approved or rejected).
  bool get _locked {
    final s = _doc?.serverStatus;
    return s != null && s != 'dikirim';
  }

  /// Project & date stay fixed once the server has ever accepted them.
  bool get _projectLocked => (_doc?.syncedVersion ?? 0) > 0;

  Map<String, Object?>? get _project {
    final all = ref.read(projectsProvider).value ?? const [];
    for (final p in all) {
      if ('${p['id']}' == '$_projectId') return p;
    }
    return null;
  }

  Map<String, Object?> _buildDocument() => {
        'projectID': _projectId,
        'date': _date,
        'checkIn': _checkIn,
        'checkOut': _checkOut,
        'lines': [
          for (final e in _lines.entries)
            {
              'uuid': e.value.uuid,
              'workerUuid': e.key,
              'status': e.value.status,
              'overtimeHours': decimalText(e.value.overtime, decimals: 1),
            },
        ],
      };

  Future<void> _save({bool close = false}) async {
    final p = ref.read(userProvider);
    if (p == null || _projectId == null) return;
    final db = ref.read(dbProvider);
    await db.saveDocument(uuid: _uuid, entity: 'attendance', userId: p.id, body: _buildDocument());
    _doc = await db.getDocument(_uuid);
    _dirty = false;
    ref.read(syncProvider.notifier).afterSave();
    if (!mounted) return;
    if (close) {
      context.pop();
    } else {
      setState(() {});
    }
  }

  /// One attendance per project per day: if it already exists on the phone, open that one.
  Future<bool> _openExisting(int projectId) async {
    final p = ref.read(userProvider);
    if (p == null) return false;
    final all = await ref.read(dbProvider).watchDocuments('attendance', p.id).first;
    for (final d in all) {
      if (d.uuid == _uuid) continue;
      final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
      if ('${body['projectID']}' == '$projectId' && '${body['date']}' == _date) {
        if (mounted) context.pushReplacement('/attendance/${d.uuid}');
        return true;
      }
    }
    return false;
  }

  Future<void> _recordEvent({required bool isCheckIn}) async {
    final p = ref.read(userProvider);
    if (p == null || _projectId == null) return;
    setState(() {
      _busy = true;
      _locationProblem = null;
    });
    try {
      // GPS starts AT THE SAME TIME as the camera: by the time the photo is
      // taken, the location has usually been acquired.
      final locationFuture = getLocation();
      final project = _project;
      final photo = await takePhoto(
        db: ref.read(dbProvider),
        userId: p.id,
        kind: isCheckIn ? 'absen_masuk' : 'absen_pulang',
        countFaces: true,
        saveToGallery: true,
        // Timemark-style caption: time, project, place, foreman.
        caption: (takenAt) async {
          final location = await locationFuture;
          final point = location.point;
          return attendanceCaption(
            at: takenAt,
            isCheckIn: isCheckIn,
            project: project,
            point: point,
            address: point == null ? null : await addressFor(point),
            locationProblem: location.problem,
            userName: p.name,
          );
        },
      );
      if (photo == null) return;
      final stamp = await DeviceTimestamp.now();
      final location = await locationFuture;
      _announceGalleryCopy(photo.gallery);
      final event = <String, Object?>{
        ...stamp.toEvent(),
        if (location.point != null) ...location.point!.toEvent() else 'isMocked': false,
        'photoUuid': photo.uuid,
        'faceCount': photo.faceCount,
      };
      setState(() {
        if (isCheckIn) {
          _checkIn = event;
        } else {
          _checkOut = event;
        }
        _locationProblem = location.problem;
      });
      await _save();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).failedWith('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tell the foreman, every time, where the photo went — some will otherwise
  /// look for it in the gallery and assume the attendance failed.
  void _announceGalleryCopy(GalleryCopy copy) {
    if (!mounted || copy == GalleryCopy.notRequested) return;
    final text = switch (copy) {
      GalleryCopy.saved => t(context).photoInGallery(galleryAlbum),
      GalleryCopy.denied => t(context).galleryDenied,
      _ => t(context).galleryFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(copy == GalleryCopy.saved ? Icons.photo_library_outlined : Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Latest send/review status (changes by itself while sync runs).
    final live = ref.watch(_liveDocProvider(_uuid)).value;
    if (live != null) _doc = live;

    final allProjects = ref.watch(projectsProvider).value ?? const [];
    final workers = ref.watch(workersProvider).value ?? const <Worker>[];
    final project = _project;
    final present = _lines.length;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldSave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(t(c).saveCrewTicks),
            content: Text(t(c).saveCrewTicksBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).discard)),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).save)),
            ],
          ),
        );
        if (!context.mounted) return;
        if (shouldSave == true) {
          await _save(close: true);
        } else if (shouldSave == false) {
          setState(() => _dirty = false);
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t(context).crewAttendance),
          actions: [if (_doc != null) Padding(padding: const EdgeInsets.only(right: 12), child: StatusBadge.sendStatus(context, _doc!.sendStatus))],
        ),
        bottomNavigationBar: _locked || _projectId == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 8, Dimens.pagePadding, 12),
                  child: SizedBox(
                    height: Dimens.minTouch + 4,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _save(close: true),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(t(context).saveWithCount(present)),
                    ),
                  ),
                ),
              ),
        body: ListView(
          padding: pagePaddingAman(context),
          children: [
            if (_doc?.sendStatus == 'rejected')
              TerraBanner(
                kind: BannerKind.danger,
                title: t(context).rejectedByServer,
                body: reasonText(context, _doc!.reason, _doc!.detail),
              ),
            if (_doc?.serverStatus != null && _doc!.serverStatus != 'dikirim')
              TerraBanner(
                kind: _doc!.serverStatus == 'ditolak' ? BannerKind.danger : BannerKind.ok,
                title: _doc!.serverStatus == 'ditolak' ? t(context).rejectedByOffice : t(context).approvedByOffice,
                body: [
                  if (_doc!.serverNote != null && _doc!.serverNote!.isNotEmpty) t(context).officeNote('${_doc!.serverNote}'),
                  t(context).attendanceLocked,
                ].join('\n'),
              ),
            ..._flagBanners(),

            // --- project --------------------------------------------------
            Text(t(context).projectLabel, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _projectId,
              isExpanded: true,
              hint: Text(t(context).pickProject),
              items: [
                for (final p in allProjects)
                  DropdownMenuItem(value: toIntOrNull(p['id']), child: Text('${p['code']} · ${p['name']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _projectLocked || _locked
                  ? null
                  : (v) async {
                      if (v == null) return;
                      if (await _openExisting(v)) return;
                      setState(() => _projectId = v);
                    },
            ),
            const SizedBox(height: 6),
            Text(longDate(DateTime.parse(_date)), style: TextStyle(color: w.muted)),
            const SizedBox(height: 16),
            if (_projectId != null && project != null && (project['latitude'] == null || project['longitude'] == null))
              TerraBanner(
                kind: BannerKind.info,
                title: t(context).projectNoLocation,
                body: t(context).projectNoLocationBody,
              ),

            if (_projectId != null) ...[
              _EventCard(
                title: t(context).checkIn,
                event: _checkIn,
                project: project,
                busy: _busy,
                active: !_locked,
                onCapture: () => _recordEvent(isCheckIn: true),
              ),
              _EventCard(
                title: t(context).checkOut,
                event: _checkOut,
                project: project,
                busy: _busy,
                active: !_locked && _checkIn != null,
                onCapture: () => _recordEvent(isCheckIn: false),
              ),
              if (_locationProblem != null)
                TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.location_off_outlined,
                  title: t(context).savedWithoutLocation,
                  body: t(context).savedWithoutLocationBody('$_locationProblem'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(t(context).crewPresent(present), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: w.ink))),
                  if (!_locked)
                    TextButton.icon(
                      onPressed: () => context.push('/workers/new?project=$_projectId'),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: Text(t(context).newWorker),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ..._crewSection(workers, project),
            ],
          ],
        ),
      ),
    );
  }

  /// Workers of this project first (main project, or absent here lately),
  /// then everyone else behind a toggle. Every worker can be ticked: crews
  /// are borrowed between sites, and the list only decides what is on top.
  List<Widget> _crewSection(List<Worker> workers, Map<String, Object?>? project) {
    final w = context.colors;
    if (workers.isEmpty) {
      return [
        TerraBanner(
          kind: BannerKind.info,
          title: t(context).noWorkersTitle,
          body: t(context).noWorkersBody,
        ),
      ];
    }
    final day = DateTime.parse(_date);
    final query = normalizeName(_crewSearch);
    bool matches(Worker k) => query.isEmpty || normalizeName(k.name).contains(query);
    final here = <Worker>[];
    final others = <Worker>[];
    for (final k in workers) {
      if (!matches(k) && !_lines.containsKey(k.uuid)) continue;
      (_lines.containsKey(k.uuid) || k.belongsTo(_projectId!, day) ? here : others).add(k);
    }
    final showOthers = _showOthers || query.isNotEmpty || here.isEmpty;
    final code = project?['code'] ?? t(context).thisProject;
    return [
      if (workers.length > 8) ...[
        TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t(context).searchWorkerName),
          onChanged: (v) => setState(() => _crewSearch = v),
        ),
        const SizedBox(height: 10),
      ],
      if (here.isEmpty && query.isEmpty)
        TerraBanner(
          kind: BannerKind.info,
          title: t(context).noWorkersForProject('$code'),
          body: t(context).noWorkersForProjectBody('$code', '${Worker.recentDays}'),
        ),
      for (final k in here) _crewRow(k),
      // A crew member who is ticked but no longer in the list (deleted by the
      // office) is still shown, so that it can be unticked.
      for (final u in _lines.keys.where((u) => !workers.any((k) => k.uuid == u)).toList())
        _crewRow(Worker(uuid: u, name: t(context).unknownWorker)),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 6),
        if (here.isNotEmpty || query.isNotEmpty)
          TextButton.icon(
            onPressed: query.isNotEmpty ? null : () => setState(() => _showOthers = !_showOthers),
            icon: Icon(showOthers ? Icons.expand_less : Icons.expand_more),
            label: Text(t(context).otherWorkers(others.length), style: TextStyle(color: w.ink)),
          ),
        if (showOthers) for (final k in others) _crewRow(k),
      ],
      if (query.isNotEmpty && here.isEmpty && others.isEmpty)
        EmptyState(message: t(context).noWorkerByName),
    ];
  }

  List<Widget> _flagBanners() {
    final raw = _doc?.flags;
    if (raw == null) return const [];
    final m = (jsonDecode(raw) as Map).cast<String, Object?>();
    final all = <String>{
      for (final v in m.values)
        if (v is List) ...v.map((e) => '$e'),
    };
    if (all.isEmpty) return const [];
    final text = all.map(_flagText).join('\n');
    return [
      TerraBanner(
        kind: BannerKind.warning,
        icon: Icons.flag_outlined,
        title: t(context).flaggedForOffice,
        body: text,
      ),
    ];
  }

  String _flagText(String k) => switch (k) {
        'DI_LUAR_RADIUS' => t(context).flagOutsideRadius,
        'LOKASI_PROYEK_KOSONG' => t(context).flagNoProjectLocation,
        'TANPA_LOKASI' => t(context).flagNoLocation,
        'GPS_PALSU' => t(context).flagMockLocation,
        'JAM_HP_SELISIH' => t(context).flagClockOff,
        'JAM_TAK_TERVERIFIKASI' => t(context).flagClockUnverified,
        'JAM_DIEDIT' => t(context).flagClockEdited,
        'JUMLAH_WAJAH_BEDA' => t(context).flagFaceCountOff,
        'FOTO_BELUM_MASUK' => t(context).flagPhotoPending,
        _ => '• $k',
      };

  Widget _crewRow(Worker k) {
    final w = context.colors;
    final b = _lines[k.uuid];
    final isSelected = b != null;
    return ListCard(
      onTap: _locked
          ? null
          : () => setState(() {
                _dirty = true;
                if (isSelected) {
                  _lines.remove(k.uuid);
                } else {
                  _lines[k.uuid] = _Line(uuid: newUuid());
                }
              }),
      child: Column(
        children: [
          Row(
            children: [
              Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: isSelected ? w.brand : w.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(k.name, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink))),
              if (k.isLocal) StatusBadge.sendStatus(context, 'pending'),
            ],
          ),
          if (isSelected) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'hadir', label: Text(t(context).fullDay)),
                    ButtonSegment(value: 'setengah', label: Text(t(context).halfDay)),
                  ],
                  selected: {b.status},
                  showSelectedIcon: false,
                  onSelectionChanged: _locked
                      ? null
                      : (s) => setState(() {
                            _dirty = true;
                            b.status = s.first;
                          }),
                ),
                const Spacer(),
                Text(t(context).overtime, style: TextStyle(color: w.muted, fontSize: 13)),
                IconButton(
                  onPressed: _locked || b.overtime <= 0
                      ? null
                      : () => setState(() {
                            _dirty = true;
                            b.overtime = (b.overtime - 0.5).clamp(0, 24);
                          }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(t(context).hoursShort(b.overtime.toStringAsFixed(1).replaceAll('.', ',')),
                    style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                IconButton(
                  onPressed: _locked || b.overtime >= 24
                      ? null
                      : () => setState(() {
                            _dirty = true;
                            b.overtime = (b.overtime + 0.5).clamp(0, 24);
                          }),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final _liveDocProvider = StreamProvider.autoDispose.family<DocumentRow?, String>(
  (ref, uuid) => ref.watch(dbProvider).watchDocument(uuid),
);

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.event,
    required this.project,
    required this.busy,
    required this.active,
    required this.onCapture,
  });

  final String title;
  final Map<String, Object?>? event;
  final Map<String, Object?>? project;
  final bool busy;
  final bool active;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final k = event;
    if (k == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: SizedBox(
          height: 64,
          child: OutlinedButton.icon(
            onPressed: active && !busy ? onCapture : null,
            icon: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_camera_outlined),
            label: Text(t(context).crewPhotoOf(title), style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    final at = DateTime.tryParse('${k['at']}');
    final lat = toDoubleOrNull(k['lat']);
    final lng = toDoubleOrNull(k['lng']);
    final projectLat = toDoubleOrNull(project?['latitude']);
    final projectLng = toDoubleOrNull(project?['longitude']);
    final radius = toDoubleOrNull(project?['geofenceRadiusM']) ?? 200;
    final distance = lat != null && lng != null && projectLat != null && projectLng != null ? distanceMeters(lat, lng, projectLat, projectLng) : null;
    final faces = toIntOrNull(k['faceCount']);

    return ListCard(
      onLongPress: active ? onCapture : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(uuid: '${k['photoUuid']}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                Text(at == null ? '–' : t(context).atTime(formatTime(at)), style: TextStyle(color: w.ink)),
                const SizedBox(height: 4),
                if (distance != null)
                  Text(
                    distance <= radius
                        ? t(context).withinRadius('${distance.round()}')
                        : t(context).outsideRadius('${distance.round()}', '${radius.round()}'),
                    style: TextStyle(color: distance <= radius ? w.okFg : w.warnFg, fontSize: 13, fontWeight: FontWeight.w600),
                  )
                else if (lat == null)
                  Text(t(context).noLocation, style: TextStyle(color: w.warnFg, fontSize: 13)),
                if (k['isMocked'] == true) Text(t(context).mockLocation, style: TextStyle(color: w.badFg, fontSize: 13)),
                if (faces != null) Text(t(context).facesInPhoto(faces), style: TextStyle(color: w.muted, fontSize: 13)),
                if (active) Text(t(context).longPressRetake, style: TextStyle(color: w.faint, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final photo = ref.watch(_photoProvider(uuid)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        color: w.surface2,
        child: photo != null && File(photo.path).existsSync()
            ? Image.file(File(photo.path), fit: BoxFit.cover, cacheWidth: 200)
            : Icon(Icons.image_outlined, color: w.muted),
      ),
    );
  }
}

final _photoProvider = FutureProvider.autoDispose.family<PhotoRow?, String>((ref, uuid) => ref.watch(dbProvider).getPhoto(uuid));
