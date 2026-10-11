import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Burns a Timemark-style caption into the bottom of a photo.
///
/// Drawn ON the phone, right after the shot, so it works with no signal. The
/// stamped image is what gets uploaded and what goes to the gallery: the office
/// reviewer sees exactly what the foreman saw.
///
/// The caption is for PEOPLE to read, not proof. The time printed is the phone
/// clock, which can be changed in Settings; the trusted time is still computed
/// by the server from the monotonic clock and flagged when it disagrees.
///
/// [image] must already be upright (EXIF orientation applied) — callers pass
/// a JPEG re-encoded by flutter_image_compress, which bakes the rotation in.
/// Returns PNG bytes; the caller compresses them back to JPEG.
Future<Uint8List> stampPhoto(Uint8List image, StampCaption caption) async {
  final codec = await ui.instantiateImageCodec(image);
  final frame = await codec.getNextFrame();
  final src = frame.image;
  final w = src.width.toDouble();
  final h = src.height.toDouble();

  // Sized against the SHORT side, so portrait and landscape shots get the
  // same caption size relative to the picture.
  final unit = (w < h ? w : h) / 100;
  final pad = unit * 3;
  final maxTextWidth = w - pad * 3;

  TextPainter paint(String text, {required double size, FontWeight weight = FontWeight.w500}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: size,
          fontWeight: weight,
          color: const Color(0xFFFFFFFF),
          height: 1.25,
          shadows: const [Shadow(blurRadius: 2, color: Color(0x99000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxTextWidth);
  }

  final headline = paint(caption.headline, size: unit * 6.2, weight: FontWeight.w800);
  final lines = [for (final l in caption.lines) paint(l, size: unit * 3.1)];
  final gap = unit * 0.8;
  final textHeight = headline.height + gap + lines.fold<double>(0, (a, t) => a + t.height + gap * 0.5);
  final bandHeight = textHeight + pad * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(src, Offset.zero, Paint());

  // Dark band so the white text stays readable over sky, concrete or sand.
  final bandTop = h - bandHeight;
  canvas.drawRect(
    Rect.fromLTWH(0, bandTop, w, bandHeight),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, bandTop),
        Offset(0, h),
        const [Color(0x66000000), Color(0xB3000000)],
      ),
  );
  // Accent bar in the TerraBot brand colour, like the web banners.
  canvas.drawRect(
    Rect.fromLTWH(pad, bandTop + pad, unit * 0.9, textHeight),
    Paint()..color = caption.accent,
  );

  var y = bandTop + pad;
  final x = pad + unit * 2.2;
  headline.paint(canvas, Offset(x, y));
  y += headline.height + gap;
  for (final t in lines) {
    t.paint(canvas, Offset(x, y));
    y += t.height + gap * 0.5;
  }

  headline.dispose();
  for (final t in lines) {
    t.dispose();
  }

  final out = await recorder.endRecording().toImage(src.width, src.height);
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  src.dispose();
  out.dispose();
  if (bytes == null) throw StateError('Cap foto gagal dibuat.');
  return bytes.buffer.asUint8List();
}

/// What is printed on the photo: one large headline and a few small lines.
class StampCaption {
  const StampCaption({required this.headline, required this.lines, this.accent = const Color(0xFF154DEC)});

  final String headline;
  final List<String> lines;
  final Color accent;
}
