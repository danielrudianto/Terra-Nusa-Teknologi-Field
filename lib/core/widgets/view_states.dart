import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

/// EMPTY list — nothing needs to be done.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: w.muted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: w.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

/// FAILED to load — DIFFERENT from empty, and has a retry button.
///
/// On a field screen the two mean opposite things: empty means there is nothing
/// to do, failed means what needs doing is not visible.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.title, this.message, this.onRetry});

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 44, color: w.badFg.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink, fontSize: 15)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: w.muted, fontSize: 14)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
          ],
        ],
      ),
    );
  }
}

/// Spinner — for a screen whose shape is NOT known in advance (a form being
/// read from the phone's own database). A screen that is a list of cards gets
/// `SkeletonCards` instead, which keeps its layout while it waits.
///
/// Held back for a beat before it appears. Most reads here finish in well
/// under that: a spinner that flashes for 40 ms and vanishes is not progress,
/// it is a blink, and the eye reads a blink as something going wrong.
class LoadingState extends StatefulWidget {
  const LoadingState({super.key});

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState> {
  static const _hold = Duration(milliseconds: 180);
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_hold, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: AnimatedOpacity(
            opacity: _show ? 1 : 0,
            duration: Dimens.motionMedium,
            curve: Curves.easeOut,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
}
