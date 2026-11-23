import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/device/camera.dart' show galleryAlbum;
import '../../core/i18n.dart';
import '../../core/providers.dart';
import 'daily_report.dart';
import 'daily_report_image.dart';

/// The daily report picture, made and handed out — shared by the Daily
/// report page and the Activity page (Daniel, 22 Nov 2026: "di sini juga
/// kasih tombol untuk download laporan hari itu").
///
/// One place, so both buttons produce the SAME picture with the same
/// texts, file name and messages.

/// A made picture: the report it came from, and the PNG (null when the day
/// has nothing to draw).
typedef DailyReportPicture = ({DailyReport report, Uint8List? png});

/// Number in the reader's language ("16,9" / "16.9").
String reportNumber(String lang, double n, int maxDecimals) =>
    NumberFormat('#,##0${maxDecimals > 0 ? '.${'#' * maxDecimals}' : ''}', lang == 'id' ? 'id' : 'en_US').format(n);

ReportTexts reportTexts(AppLocalizations l, String lang, DailyReport r) {
  String fmt(double n, int d) => reportNumber(lang, n, d);
  final day = DateTime.parse(r.date);
  final now = DateFormat('d MMM yyyy, HH.mm', lang).format(DateTime.now());
  return ReportTexts(
    title: l.drImageTitle,
    date: DateFormat('EEEE, d MMMM yyyy', lang).format(day),
    project: [r.projectCode, r.projectName].where((s) => s.isNotEmpty).join(' — '),
    client: r.clientName,
    drillTitle: l.drDrilling,
    drillSummary: l.drDrillSummary('${r.drilling.length}', fmt(r.totalDrillM, 1)),
    drillEmpty: l.drDrillEmpty,
    drillColumns: l.drDrillColumns.split('|'),
    castTitle: l.drCasting,
    castSummary: l.drCastSummary('${r.casting.length}', '${r.finishedTrucks}', fmt(r.totalCastM3, 2)),
    castEmpty: l.drCastEmpty,
    castColumns: l.drCastColumns.split('|'),
    status: {
      TruckStatus.onSite: l.drStatusOnSite,
      TruckStatus.pouring: l.drStatusPouring,
      TruckStatus.done: l.drStatusDone,
    },
    total: l.drTotal,
    truckCount: l.drTruckCount('${r.finishedTrucks}'),
    footer: l.drFooter(now),
  );
}

/// Fetch one project's day from the server and draw it.
///
/// [l] and [lang] are read by the caller BEFORE calling: this awaits the
/// network, and a context read afterwards may belong to a closed screen.
Future<DailyReportPicture> makeDailyReport(
  WidgetRef ref,
  AppLocalizations l,
  String lang,
  int projectId,
  DateTime date,
) async {
  await initializeDateFormatting(lang);
  final json = await ref.read(apiProvider).dailyReport(projectId, date);
  final report = dailyReport(json);
  final png = report.isEmpty
      ? null
      : await drawDailyReport(report, reportTexts(l, lang, report), (n, d) => reportNumber(lang, n, d));
  return (report: report, png: png);
}

void _snack(ScaffoldMessengerState m, String text, {IconData icon = Icons.check_circle_outline}) {
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

/// Save the picture to the gallery (album "TerraBot Field"), with a snackbar
/// either way.
Future<void> saveDailyReport(BuildContext context, Uint8List png, String fileName) async {
  final m = ScaffoldMessenger.of(context);
  final l = t(context);
  try {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      _snack(m, l.drSaveDenied, icon: Icons.block);
      return;
    }
    await Gal.putImageBytes(png, album: galleryAlbum, name: fileName.replaceAll('.png', ''));
    _snack(m, l.drSaved);
  } catch (e) {
    _snack(m, l.drSaveFailed('$e'), icon: Icons.error_outline);
  }
}

/// Hand the picture to the share sheet — WhatsApp is one tap from there.
Future<void> shareDailyReport(BuildContext context, Uint8List png, String fileName) async {
  final m = ScaffoldMessenger.of(context);
  final l = t(context);
  try {
    final f = File('${(await getTemporaryDirectory()).path}/$fileName');
    await f.writeAsBytes(png, flush: true);
    final res = await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path, mimeType: 'image/png')], subject: l.drImageTitle),
    );
    if (res.status == ShareResultStatus.success) _snack(m, l.drShared);
  } catch (e) {
    _snack(m, l.drShareFailed('$e'), icon: Icons.error_outline);
  }
}
