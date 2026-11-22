import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../i18n.dart';
import '../providers.dart';
import '../util/format.dart';
import '../widgets/terra_banner.dart';

/// What the OFFICE did to a log that belongs to this phone.
///
/// Reported by Daniel, 22 Nov 2026: "Dari kantor delete log, dari hp ga ke
/// refresh harus manual. Ini ngajarin orang jadi susah banget loh". The pull
/// already dropped a deleted log from the phone — silently. Whoever had the
/// log open kept looking at it and could keep typing into it, and the next
/// person to open it was only told the log was "not on this phone". Nothing
/// said that the office had removed it, who did, or why.
///
/// The pull now records what it learns in local meta, and the log screens
/// read it back and SAY it: deleted by whom, when, with the reason the office
/// typed. The same for a casting the office corrected: the phone keeps its
/// own copy, so its figures may no longer be the stored ones.
///
/// Meta, not a table: one small record per log, written by the background
/// worker as well as the screen, and read through `watchMeta` so an open
/// screen changes the moment the pull lands.
class OfficeNotice {
  const OfficeNotice({this.at, this.by, this.note});

  final DateTime? at;
  final String? by;

  /// The note from the office's audit trail ("Alasan: salah titik").
  final String? note;

  String encode() => jsonEncode({
        'at': at?.toIso8601String(),
        'by': by,
        'note': note,
      });

  /// `null` for no notice — and for a broken one: a notice that cannot be
  /// read must never take the log screen down with it.
  static OfficeNotice? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = (jsonDecode(text) as Map).cast<String, Object?>();
      return OfficeNotice(
        at: DateTime.tryParse('${m['at'] ?? ''}'),
        by: m['by']?.toString(),
        note: m['note']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

String officeDeletedKey(String uuid) => 'office_deleted:$uuid';
String officeEditedKey(String uuid) => 'office_edited:$uuid';

/// Called by the pull, inside its transaction. The key names say which
/// fields of the pulled row hold the time, the name and the note.
Future<void> recordOfficeNotice(
  AppDatabase db,
  String key,
  Map<String, Object?> row, {
  required String atKey,
  required String byKey,
  String? noteKey,
}) =>
    db.writeMeta(
      key,
      OfficeNotice(
        at: DateTime.tryParse('${row[atKey] ?? ''}'),
        by: row[byKey]?.toString(),
        note: noteKey == null ? null : row[noteKey]?.toString(),
      ).encode(),
    );

final officeDeletedProvider = StreamProvider.autoDispose.family<OfficeNotice?, String>(
  (ref, uuid) => ref.watch(dbProvider).watchMeta(officeDeletedKey(uuid)).map(OfficeNotice.decode),
);

final officeEditedProvider = StreamProvider.autoDispose.family<OfficeNotice?, String>(
  (ref, uuid) => ref.watch(dbProvider).watchMeta(officeEditedKey(uuid)).map(OfficeNotice.decode),
);

/// "Ade · 22 Nov 2026 09.40" — or just the name when the time is unknown.
String _whoAndWhen(BuildContext context, OfficeNotice n) {
  final who = n.by ?? t(context).colleague;
  final at = n.at;
  return at == null ? who : '$who · ${longDate(at)} ${formatTime(at)}';
}

/// The whole screen of a log the office deleted: what happened, and the way
/// back. Shown INSTEAD of the log — its content is gone from the server, and
/// anything typed into it would only be refused.
class DeletedByOfficeView extends StatelessWidget {
  const DeletedByOfficeView({
    super.key,
    required this.notice,
    required this.title,
    required this.next,
  });

  final OfficeNotice notice;

  /// "Catatan cor ini dihapus kantor".
  final String title;

  /// What it means for the point, in one sentence.
  final String next;

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final note = notice.note?.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TerraBanner(
          kind: BannerKind.danger,
          icon: Icons.delete_outline,
          title: title,
          body: [
            l.officeActionBy(_whoAndWhen(context, notice)),
            if (note != null && note.isNotEmpty) l.officeNote(note),
            next,
          ].join('\n'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          label: Text(l.backToList),
        ),
      ],
    );
  }
}

/// Banner at the top of a casting log the office corrected.
class EditedByOfficeBanner extends ConsumerWidget {
  const EditedByOfficeBanner({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(officeEditedProvider(uuid)).value;
    if (n == null) return const SizedBox.shrink();
    final l = t(context);
    return TerraBanner(
      kind: BannerKind.info,
      icon: Icons.edit_note,
      title: l.officeEditedTitle,
      body: l.officeEditedBody(_whoAndWhen(context, n)),
    );
  }
}
