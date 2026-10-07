import 'package:flutter/material.dart';

import '../tema/token_warna.dart';
import '../tema/ukuran.dart';

/// Kartu daftar yang dapat ditekan — `kartu-daftar` di `_mobile.scss`.
///
/// Bayangan, BUKAN garis; radius 16; MENGECIL sedikit saat ditekan. Di
/// layar sentuh warna hover tidak pernah terlihat — jari menutupi tempat
/// yang disentuhnya, dan hanya gerak yang terasa.
class KartuDaftar extends StatefulWidget {
  const KartuDaftar({super.key, required this.child, this.onTap, this.onLongPress, this.warnaTepi});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Garis kiri berwarna untuk status (mis. merah = ditolak).
  final Color? warnaTepi;

  @override
  State<KartuDaftar> createState() => _KartuDaftarState();
}

class _KartuDaftarState extends State<KartuDaftar> {
  bool _ditekan = false;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return GestureDetector(
      onTapDown: (_) => setState(() => _ditekan = true),
      onTapCancel: () => setState(() => _ditekan = false),
      onTapUp: (_) => setState(() => _ditekan = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _ditekan && widget.onTap != null ? 0.975 : 1,
        duration: Ukuran.gerakCepat,
        curve: Curves.easeOutCubic,
        child: Container(
          constraints: const BoxConstraints(minHeight: Ukuran.sentuhMinimum),
          margin: const EdgeInsets.only(bottom: 11),
          decoration: BoxDecoration(
            color: w.surface,
            borderRadius: BorderRadius.circular(Ukuran.radiusKartu),
            boxShadow: w.bayangan,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              if (widget.warnaTepi != null)
                Container(width: 4, height: 64, color: widget.warnaTepi),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
