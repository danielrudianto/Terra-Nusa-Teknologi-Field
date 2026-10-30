import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

/// Pertanyaan keberapa dari berapa — satu bentuk untuk SELURUH quiz.
///
/// Dipakai lembar "TM datang" dan lembar "Sebelum TM pertama". Dua
/// penunjuk kemajuan yang berbeda bentuk di dua layar yang sama-sama
/// bertanya membuat orangnya mengira keduanya dua hal yang berbeda.
///
/// GERAKNYA MENGISI, BUKAN MELONCAT. Ruas yang baru terisi tumbuh dari kiri
/// dalam [Dimens.motionFast] — cukup untuk menyatakan "satu maju", tidak
/// cukup untuk terasa menunggu. Kosakatanya sama dengan sisa aplikasi
/// (`core/theme/motion.dart`): tiap gerakan menyatakan sesuatu berubah,
/// bukan hiasan.
///
/// TIDAK ADA ANGKA DAN TIDAK ADA KALIMAT. "Langkah 2 dari 4" adalah satu
/// kalimat lagi untuk dibaca pada layar yang justru sedang berusaha
/// mengurangi bacaan; panjang batang yang terisi mengatakan hal yang sama
/// tanpa dibaca.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total});

  /// Pertanyaan keberapa, mulai dari 1.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final kosong = w.muted.withValues(alpha: 0.25);
    return Row(
      children: [
        for (var n = 1; n <= total; n++) ...[
          if (n > 1) const SizedBox(width: 5),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: kosong),
                  // Hanya ruas yang SEDANG terisi yang tumbuh; yang sudah
                  // lewat langsung penuh, supaya mundur satu langkah tidak
                  // menganimasikan seluruh barisnya sekaligus.
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: n <= step ? 1 : 0),
                    duration: Dimens.motionFast,
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Container(height: 6, color: w.brand),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
