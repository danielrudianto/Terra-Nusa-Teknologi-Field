import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/widgets/terra_banner.dart';

/// Log in with the same TerraBot account as the web app.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Session expired: the last user's email is already filled in.
    final p = ref.read(sessionProvider).value?.user;
    if (p != null) _email.text = p.email;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Isi email dan kata sandi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(_email.text, _password.text);
      if (mounted) context.go('/home');
    } on ApiError catch (e) {
      // Satu akun, satu HP: akun ini masih masuk di HP lain. Bukan
      // kegagalan — orangnya tinggal memilih memindahkannya ke sini.
      if (e.code == 'SESI_DI_PERANGKAT_LAIN') {
        await _askMoveDevice(e);
        return;
      }
      setState(() => _error = e.offline
          ? 'Masuk perlu sinyal. Sesudah masuk sekali, aplikasi dapat dipakai tanpa sinyal.'
          : e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Akun ini masih masuk di HP lain" — tanya dulu, baru pindahkan.
  ///
  /// Tidak dipindahkan diam-diam: salah ketik email rekan akan mengunci HP
  /// orang lain tanpa dia tahu, dan yang terkunci baru menyadarinya saat
  /// sedang mengecor.
  Future<void> _askMoveDevice(ApiError e) async {
    final w = context.colors;
    final last = _lastSeenText(e.context?['terakhir']?.toString());
    final move = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.phonelink_lock, size: 32, color: w.warnFg),
        title: const Text('Akun ini masih dipakai di HP lain', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Satu akun hanya boleh dipakai di satu HP, supaya catatan lapangan tidak bercabang.'
              '${last == null ? '' : ' HP itu terakhir aktif $last.'}',
              style: TextStyle(color: w.ink, height: 1.4),
            ),
            const SizedBox(height: 12),
            const TerraBanner(
              kind: BannerKind.info,
              icon: Icons.cloud_upload_outlined,
              title: 'Data di HP lama tidak hilang',
              body: 'HP itu masih dapat mengirim sisa antreannya, hanya tidak boleh mencatat yang baru. Bila HP itu yang sebenarnya Anda pakai, batalkan saja dan masuk dari sana.',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pindahkan ke HP ini')),
        ],
      ),
    );
    if (move != true || !mounted) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(_email.text, _password.text, moveDevice: true);
      if (mounted) context.go('/home');
    } on ApiError catch (e2) {
      setState(() => _error = e2.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "12 menit lalu" dari waktu ISO yang dikirim server; null bila tidak ada.
  static String? _lastSeenText(String? iso) {
    if (iso == null) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final d = DateTime.now().difference(t);
    if (d.isNegative) return null;
    if (d.inMinutes < 1) return 'barusan';
    if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final sessionExpired = ref.watch(sessionProvider).value?.sessionExpired ?? false;
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
                    if (sessionExpired)
                      const TerraBanner(
                        kind: BannerKind.info,
                        title: 'Data di HP ini aman',
                        body: 'Masuk lagi dengan akun yang sama supaya antreannya terkirim.',
                      ),
                    if (_error != null) TerraBanner(kind: BannerKind.danger, title: 'Belum dapat masuk', body: _error),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _checkIn(),
                      decoration: InputDecoration(
                        labelText: 'Kata sandi',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: Dimens.minTouch + 4,
                      child: FilledButton(
                        onPressed: _busy ? null : _checkIn,
                        child: _busy
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
