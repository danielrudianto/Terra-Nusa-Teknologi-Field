import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/device/camera.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/reasons.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';

/// Register a new worker, or correct an existing one.
///
/// Workers belong to the company: anyone allowed to register workers may also
/// correct any of them, whoever registered it.
///
/// Document body = EXACTLY `DataPekerja` on the server (name, projectID, phone,
/// facePhotoUuid, note, isActive). Other fields are rejected by the server.
class WorkerForm extends ConsumerStatefulWidget {
  const WorkerForm({super.key, required this.uuid, this.projectId});

  final String? uuid;

  /// Main project to prefill when registering, e.g. from the attendance form.
  final int? projectId;

  @override
  ConsumerState<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends ConsumerState<WorkerForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  late final String _uuid = widget.uuid ?? newUuid();
  late int? _projectId = widget.projectId;
  String? _photoUuid;
  String? _photoPath;
  int? _faceCount;
  int? _serverVersion;
  bool _serverOnly = false;
  bool _loading = true;
  bool _saving = false;
  String? _rejectReason;

  /// Shown after the first tap on Simpan; a second tap saves anyway.
  List<Worker>? _duplicates;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uuid == null && _projectId == null) {
      _projectId = await ref.read(myProjectProvider.future);
    }
    if (widget.uuid != null) {
      final db = ref.read(dbProvider);
      final doc = await db.getDocument(_uuid);
      Map<String, Object?>? body;
      if (doc != null) {
        body = (jsonDecode(doc.body) as Map).cast<String, Object?>();
        if (doc.sendStatus == 'rejected') _rejectReason = reasonText(doc.reason, doc.detail);
      } else {
        body = await db.getMaster('worker', _uuid);
        _serverOnly = body != null;
        _serverVersion = toIntOrNull(body?['clientVersion']);
      }
      if (body != null) {
        _name.text = '${body['name'] ?? ''}';
        _phone.text = '${body['phone'] ?? ''}';
        _note.text = '${body['note'] ?? ''}';
        _projectId = toIntOrNull(body['projectID']);
        _photoUuid = body['facePhotoUuid']?.toString();
        if (_photoUuid != null) _photoPath = (await db.getPhoto(_photoUuid!))?.path;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _canEdit {
    final session = ref.read(sessionProvider).value;
    if (session == null) return false;
    return session.allows('field_worker', 'create') || session.allows('field_worker', 'update');
  }

  Future<void> _takePhoto() async {
    final p = ref.read(userProvider);
    if (p == null) return;
    try {
      final f = await takePhoto(db: ref.read(dbProvider), userId: p.id, kind: 'wajah', countFaces: true);
      if (f == null) return;
      setState(() {
        _photoUuid = f.uuid;
        _photoPath = f.path;
        _faceCount = f.faceCount;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kamera gagal: $e')));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _rejectReason = 'Isi nama pekerja.');
      return;
    }
    final phone = _phone.text.trim();
    // Only when registering: an edit of an existing worker is not a new person.
    if (widget.uuid == null && _duplicates == null) {
      final all = ref.read(workersProvider).value ?? const <Worker>[];
      final same = possibleDuplicates(all, uuid: _uuid, name: name, phone: phone);
      if (same.isNotEmpty) {
        setState(() => _duplicates = same);
        return;
      }
    }
    final p = ref.read(userProvider);
    if (p == null) return;
    setState(() => _saving = true);
    await ref.read(dbProvider).saveDocument(
      uuid: _uuid,
      entity: 'worker',
      userId: p.id,
      serverVersion: _serverOnly ? (_serverVersion ?? 1) : null,
      body: {
        'name': name,
        'projectID': _projectId,
        'phone': phone.isEmpty ? null : phone,
        'facePhotoUuid': _photoUuid,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'isActive': true,
      },
    );
    ref.read(syncProvider.notifier).afterSave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text('$name disimpan. Terkirim otomatis saat ada sinyal.')),
          ],
        ),
      ),
    );
    context.pop();
  }

  Widget _projectField(bool canEdit) {
    final all = ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[];
    // Ongoing projects only, plus the one already chosen even if it has since
    // gone into retention, so the field never shows an empty value.
    final choices = [
      for (final p in all)
        if (!isRetentionProject(p) || toIntOrNull(p['id']) == _projectId) p,
    ];
    final known = choices.any((p) => toIntOrNull(p['id']) == _projectId);
    return DropdownButtonFormField<int?>(
      initialValue: known ? _projectId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Proyek utama (opsional)'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Tanpa proyek utama')),
        for (final p in choices)
          DropdownMenuItem<int?>(
            value: toIntOrNull(p['id']),
            child: Text('${p['code']} · ${p['name']}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: canEdit ? (v) => setState(() => _projectId = v) : null,
    );
  }

  Widget _duplicateBanner() {
    final names = _duplicates!.take(5).map((d) {
      final phone = d.phone == null || d.phone!.isEmpty ? '' : ' (${d.phone})';
      return '• ${d.name}$phone';
    }).join('\n');
    final more = _duplicates!.length > 5 ? '\n• dan ${_duplicates!.length - 5} lainnya' : '';
    return TerraBanner(
      kind: BannerKind.warning,
      icon: Icons.people_alt_outlined,
      title: 'Mungkin sudah terdaftar',
      body: 'Nama atau nomor HP ini mirip pekerja yang sudah ada:\n$names$more\n\n'
          'Kalau orangnya sama, batalkan dan pakai pekerja yang sudah ada. '
          'Kalau memang orang lain, tekan tombol simpan sekali lagi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final canEdit = !_loading && _canEdit;
    return Scaffold(
      appBar: AppBar(title: Text(widget.uuid == null ? 'Pekerja baru' : 'Pekerja')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Dimens.pagePadding),
              children: [
                if (_rejectReason != null) TerraBanner(kind: BannerKind.danger, title: 'Perlu diperbaiki', body: _rejectReason),
                if (!_loading && !canEdit)
                  const TerraBanner(
                    kind: BannerKind.info,
                    title: 'Hanya dapat dilihat',
                    body: 'Akun Anda tidak punya izin mendaftarkan atau mengubah pekerja. Minta kantor menambahkan izinnya.',
                  ),
                Center(
                  child: GestureDetector(
                    onTap: canEdit ? _takePhoto : null,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: w.surface2,
                        borderRadius: BorderRadius.circular(70),
                        image: _photoPath != null
                            ? DecorationImage(image: FileImage(File(_photoPath!)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _photoPath == null ? Icon(Icons.add_a_photo_outlined, size: 40, color: w.muted) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_faceCount != null && _faceCount != 1)
                  TerraBanner(
                    kind: BannerKind.warning,
                    title: _faceCount == 0 ? 'Wajah tidak terdeteksi' : '$_faceCount wajah terdeteksi',
                    body: 'Foto wajah dipakai kantor untuk mencocokkan kru. Ambil ulang dengan satu wajah, menghadap kamera.',
                    action: TextButton(onPressed: _takePhoto, child: const Text('Ulang')),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  enabled: canEdit,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama lengkap'),
                  onChanged: (_) {
                    if (_duplicates != null) setState(() => _duplicates = null);
                  },
                ),
                const SizedBox(height: 14),
                _projectField(canEdit),
                const SizedBox(height: 14),
                TextField(
                  controller: _phone,
                  enabled: canEdit,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
                  onChanged: (_) {
                    if (_duplicates != null) setState(() => _duplicates = null);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Catatan (mis. tukang besi, operator)'),
                ),
                const SizedBox(height: 24),
                if (_duplicates != null) _duplicateBanner(),
                if (canEdit)
                  SizedBox(
                    height: Dimens.minTouch + 4,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_duplicates == null ? 'Simpan' : 'Tetap simpan sebagai pekerja baru'),
                    ),
                  ),
              ],
            ),
    );
  }
}
