import 'package:flutter/material.dart';

import '../tema/token_warna.dart';

/// Judul + deskripsi di atas isi halaman — `header-title` di web.
class KepalaHalaman extends StatelessWidget {
  const KepalaHalaman({super.key, required this.judul, this.deskripsi, this.aksi});

  final String judul;
  final String? deskripsi;
  final Widget? aksi;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: w.ink)),
                if (deskripsi != null) ...[
                  const SizedBox(height: 2),
                  Text(deskripsi!, style: TextStyle(fontSize: 14, color: w.muted)),
                ],
              ],
            ),
          ),
          if (aksi != null) aksi!,
        ],
      ),
    );
  }
}
