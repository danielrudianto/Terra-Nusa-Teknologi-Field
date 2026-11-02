import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

/// Swipe-to-confirm: one control for an action that cannot be taken back.
///
/// WHERE IT BELONGS
///
/// Closing a drill log and closing a casting log, and nowhere else. Both
/// stamp a time that later stands as field EVIDENCE, and one stray tap there
/// stores a time that never happened. Anything repeatable — adding a truck,
/// saving a reading, taking a photo — keeps an ordinary button: a drag
/// gesture performed twenty times a day stops being a guard and becomes a
/// punishment.
///
/// WHY NOT AN "ARE YOU SURE?" DIALOG
///
/// A dialog asks for one more tap, and a second tap where the thumb already
/// expects one is a reflex, not a decision. A drag asks for a movement that
/// cannot happen by brushing the screen.
///
/// THE THRESHOLD IS 70%, NOT THE FULL TRACK
///
/// This runs at a borehole: dusty hands, sometimes wet, sometimes gloved.
/// Capacitive touch is least reliable precisely on a DRAG — contact breaks
/// halfway. A full-width threshold means repeated failure for someone whose
/// intent was right all along; 70% leaves room for that without becoming
/// something a sleeve can trigger.
///
/// IT LOCKS WHILE [onConfirm] RUNS
///
/// Once the drag lands, the control is dead until [onConfirm] answers. This
/// is not tidiness: closing a log once reported "saved" over a log that had
/// not been stored, and a control that can be dragged again while its request
/// is still in flight is exactly how a double close is born.
///
/// [onConfirm] ANSWERS `false` WHEN THE ACTION DID NOT HAPPEN — a required
/// field still empty, for instance. The thumb then slides back and can be
/// dragged again. Without that way back, one failed validation locks the
/// control forever inside a dialog that is still open: a dead end whose only
/// exit is abandoning the whole entry.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.doneLabel,
    this.icon = Icons.arrow_forward,
    this.danger = false,
    this.enabled = true,
  });

  /// The invitation, e.g. "Geser untuk selesai bor".
  final String label;

  /// Called when the drag lands; never called again while it is still
  /// pending.
  ///
  /// Answer `true` when the action HAPPENED — the thumb stays locked at the
  /// end. Answer `false` when it did not; the thumb returns to the start.
  final Future<bool> Function() onConfirm;

  /// Shown once locked. Null keeps [label].
  final String? doneLabel;

  final IconData icon;

  /// Paints the track in the error colour — for what truly cannot be undone.
  final bool danger;

  /// Dead and undraggable, e.g. while a required field is still empty.
  final bool enabled;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> {
  static const double _height = 56;
  static const double _threshold = 0.7;

  double _offset = 0;
  bool _done = false;
  bool _busy = false;
  bool _dragging = false;

  Future<void> _settle(double track) async {
    if (_offset < track * _threshold) {
      // Slide back GENTLY rather than snapping: letting go halfway must read
      // as "not finished", not as "it failed".
      setState(() {
        _offset = 0;
        _dragging = false;
      });
      return;
    }

    setState(() {
      _offset = track;
      _dragging = false;
      _busy = true;
    });

    // Defaults to NOT done, so anything thrown sends the thumb back: a
    // control locked at the end after its action failed states something
    // that never happened.
    var confirmed = false;
    try {
      confirmed = await widget.onConfirm();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _done = confirmed;
          if (!confirmed) _offset = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final live = widget.enabled && !_done && !_busy;
    final accent = widget.danger ? w.badFg : w.okFg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final track = (constraints.maxWidth - _height).clamp(0.0, double.infinity);
        final progress = track == 0 ? 0.0 : (_offset / track).clamp(0.0, 1.0);

        return Semantics(
          button: true,
          enabled: live,
          label: _done ? (widget.doneLabel ?? widget.label) : widget.label,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: live ? accent.withValues(alpha: 0.10) : w.faint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Dimens.radiusBanner),
              border: Border.all(
                color: live ? accent.withValues(alpha: 0.35) : Colors.transparent,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    // The sentence is pushed clear of the thumb so a dragging
                    // finger never covers it.
                    padding: const EdgeInsets.only(left: _height, right: Dimens.pagePadding),
                    child: AnimatedOpacity(
                      duration: Dimens.motionFast,
                      // Fades as the drag advances: someone already dragging
                      // no longer needs to be told to drag.
                      opacity: _done ? 1 : (1 - progress).clamp(0.35, 1.0),
                      child: Text(
                        _done ? (widget.doneLabel ?? widget.label) : widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: live || _done ? accent : w.faint,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : Dimens.motionMedium,
                  curve: Curves.easeOut,
                  left: _offset,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragStart: live ? (_) => setState(() => _dragging = true) : null,
                    onHorizontalDragUpdate: live
                        ? (d) => setState(() {
                            _offset = (_offset + d.delta.dx).clamp(0.0, track);
                          })
                        : null,
                    onHorizontalDragEnd: live ? (_) => _settle(track) : null,
                    child: Container(
                      width: _height,
                      height: _height,
                      decoration: BoxDecoration(
                        color: live || _done ? accent : w.faint,
                        borderRadius: BorderRadius.circular(Dimens.radiusBanner),
                      ),
                      child: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _done ? Icons.check : widget.icon,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
