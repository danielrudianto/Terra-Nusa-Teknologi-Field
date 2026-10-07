import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/jaringan/galat.dart';
import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/widget/banner_terra.dart';

/// Masuk dengan akun TerraBot yang sama dengan web.
class HalamanMasuk extends ConsumerStatefulWidget {
  const HalamanMasuk({super.key});

  @override
  ConsumerState<HalamanMasuk> createState() => _HalamanMasukState();
}

class _HalamanMasukState extends ConsumerState<HalamanMasuk> {
  final _email = TextEditingController();
  final _sandi = TextEditingController();
  bool _proses = false;
  bool _lihatSandi = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    // Sesi habis: email pengguna terakhir sudah terisi.
    final p = ref.read(sesiProvider).value?.pengguna;
    if (p != null) _email.text = p.email;
  }

  @override
  void dispose() {
    _email.dispose();
    _sandi.dispose();
    super.dispose();
  }

  Future<void> _masuk() async {
    if (_email.text.trim().isEmpty || _sandi.text.isEmpty) {
      setState(() => _galat = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _proses = true;
      _galat = null;
    });
    try {
      await ref.read(sesiProvider.notifier).masuk(_email.text, _sandi.text);
      if (mounted) context.go('/beranda');
    } on GalatApi catch (e) {
      setState(() => _galat = e.tanpaJaringan
          ? 'Masuk perlu sinyal. Sesudah masuk sekali, aplikasi dapat dipakai tanpa sinyal.'
          : e.pesan);
    } catch (e) {
      setState(() => _galat = '$e');
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final sesiHabis = ref.watch(sesiProvider).value?.sesiHabis ?? false;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.foundation, size: 56, color: w.brand),
                    const SizedBox(height: 10),
                    Text('TerraBot Field',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: w.ink)),
                    Text('Absensi kru & log pengecoran',
                        textAlign: TextAlign.center, style: TextStyle(color: w.muted)),
                    const SizedBox(height: 28),
                    if (sesiHabis)
                      const BannerTerra(
                        jenis: JenisBanner.info,
                        judul: 'Data di HP ini aman',
                        isi: 'Masuk lagi dengan akun yang sama supaya antreannya terkirim.',
                      ),
                    if (_galat != null) BannerTerra(jenis: JenisBanner.bahaya, judul: 'Belum dapat masuk', isi: _galat),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _sandi,
                      obscureText: !_lihatSandi,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _masuk(),
                      decoration: InputDecoration(
                        labelText: 'Kata sandi',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _lihatSandi = !_lihatSandi),
                          icon: Icon(_lihatSandi ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: Ukuran.sentuhMinimum + 4,
                      child: FilledButton(
                        onPressed: _proses ? null : _masuk,
                        child: _proses
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : const Text('Masuk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
