import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';

/// Kerangka dengan navigasi bawah. Lencana di tab Antrean = jumlah dokumen
/// + foto yang belum terkirim, supaya mandor tahu tanpa membuka apa pun.
class KerangkaUtama extends ConsumerWidget {
  const KerangkaUtama({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final belum = (ref.watch(jumlahBelumTerkirimProvider).value ?? 0) +
        (ref.watch(jumlahFotoBelumTerkirimProvider).value ?? 0);
    Widget lencana(IconData ikon) =>
        Badge(isLabelVisible: belum > 0, label: Text(belum > 99 ? '99+' : '$belum'), child: Icon(ikon));
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
          const NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg),
            label: 'Absensi',
          ),
          const NavigationDestination(
            icon: Icon(Icons.foundation_outlined),
            selectedIcon: Icon(Icons.foundation),
            label: 'Cor',
          ),
          NavigationDestination(
            icon: lencana(Icons.cloud_upload_outlined),
            selectedIcon: lencana(Icons.cloud_upload),
            label: 'Antrean',
          ),
        ],
      ),
    );
  }
}
