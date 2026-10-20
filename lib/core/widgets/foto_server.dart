import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n.dart';
import '../network/api_error.dart';
import '../providers.dart';
import '../theme/color_tokens.dart';

/// FOTO LAPANGAN DARI SERVER — untuk HP yang tidak mengambilnya sendiri.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA ADA — Daniel, 20 Oktober 2026
/// ──────────────────────────────────────────────────────────────────────────
///
///     "sama ini juga untuk waktu pantau cor, pengen ada tabelnya gitu dong
///      bang. jadi bisa monitor juga. sekalian bisa lihat surat jalannya
///      disana"
///
/// Foto surat jalan sudah lama diambil di lokasi, tetapi berkasnya tinggal
/// di HP yang MENCATAT — `_CastingPhoto` di formulir cor membacanya dari
/// penyimpanan setempat. HP lain tidak punya berkas itu sama sekali, jadi
/// satu-satunya halaman yang benar-benar ingin dibaca orang kantor selama
/// ini hanya dapat dilihat dengan meminta kru memotretnya lagi lewat
/// WhatsApp.
///
/// Diambil HANYA SAAT DIKETUK, bukan saat tabelnya digambar: satu cor dapat
/// berisi dua belas TM, dan menarik dua belas foto sekaligus di jaringan
/// lokasi berarti layar pantau berhenti bekerja demi gambar yang mungkin
/// tidak dibuka siapa pun.
final fotoServerProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, uuid) async {
    final isi = await ref.read(apiProvider).fieldPhoto(uuid);
    return Uint8List.fromList(isi);
  },
);

/// Buka satu foto lapangan selayar penuh, dapat dicubit untuk diperbesar.
void bukaFotoServer(BuildContext context, String uuid, String judul) {
  showDialog<void>(
    context: context,
    builder: (_) => _LayarFoto(uuid: uuid, judul: judul),
  );
}

class _LayarFoto extends ConsumerWidget {
  const _LayarFoto({required this.uuid, required this.judul});

  final String uuid;
  final String judul;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final foto = ref.watch(fotoServerProvider(uuid));

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    judul,
                    style: TextStyle(fontWeight: FontWeight.w800, color: w.ink),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: w.line),
          Flexible(
            child: foto.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Foto yang SUDAH LEWAT MASA SIMPAN (410) bukan kegagalan
              // jaringan, dan menyebutnya "gagal memuat" membuat orang
              // mencoba lagi berkali-kali untuk berkas yang sudah tidak ada.
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(
                      e is ApiError && e.status == 410
                          ? Icons.auto_delete_outlined
                          : Icons.cloud_off,
                      color: w.muted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e is ApiError && e.status == 410
                          ? t(context).photoExpired
                          : t(context).photoFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: w.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              data: (isi) => InteractiveViewer(
                maxScale: 6,
                child: Image.memory(isi, fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keping kecil "Surat jalan" yang membuka fotonya.
///
/// SEBUAH KEPING, bukan gambar kecil: gambar kecil surat jalan tidak dapat
/// dibaca pada ukuran apa pun yang pantas di dalam tabel — yang terbaca
/// hanyalah bahwa fotonya ADA — sedangkan keping bernama menyatakan hal yang
/// sama tanpa menarik satu pun berkas lebih dulu.
class KepingFoto extends StatelessWidget {
  const KepingFoto({
    super.key,
    required this.uuid,
    required this.label,
    this.ikon = Icons.receipt_long,
  });

  final String uuid;
  final String label;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => bukaFotoServer(context, uuid, label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: w.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: w.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 13, color: w.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: w.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
