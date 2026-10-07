import 'package:flutter/material.dart';

import '../tema/token_warna.dart';

/// Daftar KOSONG — tidak ada yang perlu dikerjakan.
class KeadaanKosong extends StatelessWidget {
  const KeadaanKosong({super.key, required this.pesan, this.ikon = Icons.inbox_outlined});

  final String pesan;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Icon(ikon, size: 48, color: w.muted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center, style: TextStyle(color: w.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

/// GAGAL memuat — BERBEDA dari kosong, dan punya tombol coba lagi.
///
/// Di layar lapangan keduanya berlawanan arti: kosong berarti tidak ada
/// yang perlu dikerjakan, gagal berarti yang perlu dikerjakan tidak terlihat.
class KeadaanGagal extends StatelessWidget {
  const KeadaanGagal({super.key, required this.judul, this.pesan, this.onCobaLagi});

  final String judul;
  final String? pesan;
  final VoidCallback? onCobaLagi;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 44, color: w.badFg.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(judul, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink, fontSize: 15)),
          if (pesan != null) ...[
            const SizedBox(height: 4),
            Text(pesan!, textAlign: TextAlign.center, style: TextStyle(color: w.muted, fontSize: 14)),
          ],
          if (onCobaLagi != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: onCobaLagi, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
          ],
        ],
      ),
    );
  }
}

class KeadaanMuat extends StatelessWidget {
  const KeadaanMuat({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(child: CircularProgressIndicator()),
      );
}
