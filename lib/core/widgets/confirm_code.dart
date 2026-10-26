import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../theme/color_tokens.dart';

/// Awalan kode titik yang BOLEH ditampilkan: bagian yang sama untuk seluruh
/// titik di proyek, dan karenanya tidak membedakan apa pun.
///
/// Gunanya memperpendek yang harus diketik di lapangan, sambil menjaga
/// seluruh bagian yang membedakan tetap diketik sendiri. `PP.B52` di proyek
/// berisi `PP.B1..PP.B60` menyisakan `52` untuk diketik.
///
/// Tiga batas, dan ketiganya ada alasannya:
///
/// 1. Hanya sejauh awalan yang sama. Lebih dari itu berarti menampilkan
///    bagian yang membedakan titik ini dari titik lain — yaitu justru
///    jawaban yang sedang ditanyakan.
/// 2. Berhenti sebelum angka pertama. Dua titik bersebelahan sering hanya
///    berbeda di digit terakhir (`PP.B52` dan `PP.B54`), sehingga awalan
///    yang sama bisa sampai `PP.B5` dan yang tersisa cuma satu ketukan —
///    satu dari sepuluh kemungkinan, yang berarti pemeriksaan ini tidak
///    lagi memeriksa apa-apa. Seluruh angka selalu diketik.
/// 3. Minimal dua karakter tersisa, apa pun hasil dua aturan di atas.
///
/// [all] boleh memuat [code] sendiri; ia dilewati.
String sharedCodePrefix(String code, Iterable<String> all) {
  var n = code.length;
  for (final other in all) {
    if (other == code) continue;
    var i = 0;
    final m = n < other.length ? n : other.length;
    while (i < m && code.codeUnitAt(i) == other.codeUnitAt(i)) {
      i++;
    }
    if (i < n) n = i;
  }
  final angka = code.indexOf(RegExp(r'[0-9]'));
  if (angka >= 0 && angka < n) n = angka;
  if (n > code.length - 2) n = code.length - 2;
  return n <= 0 ? '' : code.substring(0, n);
}

/// Dua kode dianggap sama kalau tinggal huruf dan angkanya saja yang
/// dibandingkan: besar-kecil huruf, spasi, titik dan tanda hubung tidak
/// pernah menjadi alasan menolak orang yang berdiri di titik yang benar.
String _inti(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Minta nomor titik diketik ulang sebelum pekerjaan di titik itu dimulai.
///
/// KENAPA MENGETIK, BUKAN "ANDA YAKIN?"
///
/// Salahnya bukan salah baca, melainkan salah tap baris di daftar. Siapa pun
/// yang salah tap akan sama yakinnya, jadi pertanyaan yakin-atau-tidak
/// dijawab "yakin" dan log cor masuk ke titik yang salah — ketahuan berhari
/// hari kemudian, waktu angkanya sudah dipakai menghitung volume.
///
/// Mengetik adalah kanal kedua yang tidak ikut salah: yang diketik datang
/// dari tiang di depan mata, bukan dari daftar yang salah tersentuh. Karena
/// itu kode yang dipilih TIDAK ditampilkan di mana pun sebelum jawabannya
/// masuk — dialog yang memperlihatkan jawabannya hanya menguji kemampuan
/// menyalin.
///
/// Begitu yang diketik tidak cocok, kode yang dipilih justru DITAMPILKAN:
/// pada saat itu ia bukan lagi jawaban yang bisa disalin, melainkan satu
/// satunya keterangan yang menjelaskan apa yang baru saja terjadi — "di
/// daftar Anda memilih PP.B54, yang Anda ketik PP.B52".
///
/// Mengembalikan `true` hanya kalau kodenya diketik dan cocok. Dialog yang
/// ditutup — tombol kembali, sentuh di luar, Batal — adalah TIDAK.
Future<bool> askCodeConfirm(
  BuildContext context, {
  required String code,
  required Iterable<String> allCodes,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CodeDialog(code: code, prefix: sharedCodePrefix(code, allCodes)),
  );
  return answer ?? false;
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.code, required this.prefix});

  final String code;
  final String prefix;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  // Pengendali teks hidup di State dialognya sendiri, bukan di pemanggil —
  // sama seperti number_dialog, dan karena alasan yang sama.
  final _input = TextEditingController();
  bool _salah = false;

  /// Bagian yang harus diketik: kode penuh dikurangi awalan yang tampil.
  String get _sisa => widget.code.substring(widget.prefix.length);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Apa yang SEBENARNYA diketik orangnya, sebagai kode penuh.
  ///
  /// Tidak boleh sekadar awalan + isian: `_periksa` sengaja menerima kode
  /// PENUH yang diketik tanpa sadar ada awalan yang sudah tampil, dan
  /// menempelkan awalan di depannya menghasilkan "PP.BPP.B54" — satu
  /// satunya kalimat yang tugasnya menerangkan apa yang baru terjadi
  /// malah mencetak omong kosong.
  String _diketikPenuh() {
    final diketik = _input.text.trim();
    final penuh = '${widget.prefix}$diketik';
    // Sudah memuat awalannya sendiri → pakai apa adanya.
    return _inti(diketik).startsWith(_inti(widget.prefix)) &&
            widget.prefix.isNotEmpty
        ? diketik
        : penuh;
  }

  void _periksa() {
    final diketik = _input.text.trim();
    if (diketik.isEmpty) return;
    // Dibandingkan sebagai kode PENUH, supaya orang yang mengetik
    // "PP.B52" lengkap — tidak menyadari ada awalan yang sudah tampil —
    // tetap diterima.
    final cocok = _inti(diketik) == _inti(_sisa) || _inti(diketik) == _inti(widget.code);
    if (cocok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _salah = true);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final hanyaAngka = RegExp(r'^[0-9]+$').hasMatch(_sisa);
    return AlertDialog(
      // Papan tuts naik seketika karena `autofocus`. Tanpa ini, isi
      // dialog tidak menggulung dan tombolnya terpotong di layar pendek
      // atau pada posisi mendatar.
      scrollable: true,
      icon: const Icon(Icons.keyboard, size: 32),
      title: Text(t(context).confirmPointCodeTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context).confirmPointCodeBody),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            keyboardType: hanyaAngka ? TextInputType.number : TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _periksa(),
            onChanged: (_) {
              if (_salah) setState(() => _salah = false);
            },
            // Tempel dimatikan: menempel kode yang disalin dari daftar
            // mengembalikan dialog ini menjadi sekadar "Anda yakin?".
            enableInteractiveSelection: false,
            contextMenuBuilder: (_, _) => const SizedBox.shrink(),
            decoration: InputDecoration(
              labelText: t(context).confirmPointCodeField,
              prefixText: widget.prefix.isEmpty ? null : widget.prefix,
              prefixStyle: TextStyle(color: w.muted, fontWeight: FontWeight.w800, fontSize: 16),
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
          ),
          if (_salah) ...[
            const SizedBox(height: 12),
            Text(
              t(context).confirmPointCodeMismatch(widget.code, _diketikPenuh()),
              style: TextStyle(color: w.badFg, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context).cancel)),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (_, v, _) => FilledButton(
            onPressed: v.text.trim().isEmpty ? null : _periksa,
            child: Text(t(context).confirmPointCodeConfirm),
          ),
        ),
      ],
    );
  }
}
