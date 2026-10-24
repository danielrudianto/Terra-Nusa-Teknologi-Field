import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'error_reporter.dart';

/// A small on-phone log of errors and notable events, for "it went wrong on
/// site" — there is no crash-reporting service, and a foreman cannot read
/// logcat. Settings has "Kirim log" that shares the file over WhatsApp.
///
/// One file, capped at ~200 kB (the oldest half is dropped when it grows
/// past that), so it can never fill the phone. Nothing personal goes in:
/// no names, no coordinates, no photos — only what happened and when.
class AppLog {
  AppLog._();

  static const _maxBytes = 200 * 1024;
  static File? _file;
  static final _pending = <String>[];
  static Timer? _flush;

  static Future<File> file() async {
    final f = _file;
    if (f != null) return f;
    final dir = await getApplicationSupportDirectory();
    return _file = File('${dir.path}/terrabot-field.log');
  }

  /// Route every uncaught Flutter and Dart error here. Called once by main().
  static void installErrorHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error('flutter', details.exceptionAsString(), details.stack);
      // Ikut dikirim ke server — lihat `ErrorReporter`. Yang tak tertangkap
      // adalah galat yang paling tidak terlihat dari kantor: tidak ada
      // kalimat di layar yang dapat dikeluhkan orang, hanya layar yang
      // membeku atau tombol yang tidak berbuat apa-apa.
      ErrorReporter.record(fallbackKey: 'crash.flutter');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      error('dart', e, st);
      ErrorReporter.record(fallbackKey: 'crash.dart');
      return false; // keep the default handling (prints in debug)
    };
  }

  static void info(String tag, String message) => _write('I', tag, message);

  static void error(String tag, Object e, [StackTrace? st]) {
    final lines = st == null ? '' : '\n${st.toString().split('\n').take(12).join('\n')}';
    _write('E', tag, '$e$lines');
  }

  static void _write(String level, String tag, String message) {
    final t = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    _pending.add('$t $level [$tag] $message');
    debugPrint(_pending.last);
    // Batched: an error storm must not hammer the disk.
    _flush ??= Timer(const Duration(milliseconds: 400), () {
      _flush = null;
      unawaited(flush());
    });
  }

  static Future<void> flush() async {
    if (_pending.isEmpty) return;
    final chunk = '${_pending.join('\n')}\n';
    _pending.clear();
    try {
      final f = await file();
      await f.writeAsString(chunk, mode: FileMode.append, flush: true);
      if (await f.length() > _maxBytes) {
        final text = await f.readAsString();
        await f.writeAsString(text.substring(text.length ~/ 2), flush: true);
      }
    } catch (_) {
      // A log that cannot be written is not worth crashing over.
    }
  }

  /// The log text, newest last; empty when nothing was ever logged.
  static Future<String> read() async {
    await flush();
    try {
      final f = await file();
      return await f.exists() ? await f.readAsString() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    _pending.clear();
    try {
      final f = await file();
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Pencatatnya sendiri yang gagal — tidak ada tempat untuk
      // mencatatnya, dan melempar dari sini akan menggagalkan tindakan
      // yang memanggilnya hanya karena berkas catatan tidak terhapus.
    }
  }
}
