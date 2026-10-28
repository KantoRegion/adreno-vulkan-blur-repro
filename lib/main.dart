// Minimal repro for flutter/flutter#192002.
//
// Raster-thread SIGSEGV in /vendor/lib64/hw/vulkan.adreno.so at
// qglinternal::vkCmdBeginRenderPass. OnePlus 15R (CPH2769), Adreno 829,
// Android 16. Crashes in about 6 seconds.
//
//   flutter create repro   (then paste this over lib/main.dart)
//   flutter build apk --release && flutter install
//   adb logcat -b crash
//
// Impeller is left at its default; no EnableImpeller entry in the manifest.
// No packages, no assets.
//
// Two ingredients, both required. Each was verified by removing it:
//   1. a ui.Picture containing ~500 MaskFilter.blur draws;
//   2. that picture replayed inside saveLayer offscreens whose bounds
//      change every frame.
// Either one without the other runs indefinitely.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Blurred draws recorded into the picture. 500 crashes; 25 does not.
const int kBlurredLines = 500;

/// Offscreen layers opened per frame. 10 crashes in ~6s, 1 in ~36s.
const int kLayersPerFrame = 10;

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReproPage(),
    ));

class ReproPage extends StatefulWidget {
  const ReproPage({super.key});

  @override
  State<ReproPage> createState() => _ReproPageState();
}

class _ReproPageState extends State<ReproPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      setState(() => _t = e.inMilliseconds / 1000.0);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: CustomPaint(size: Size.infinite, painter: _Painter(_t)),
      );
}

class _Painter extends CustomPainter {
  _Painter(this.t);

  final double t;

  /// Recorded once, then replayed inside every layer below.
  static ui.Picture? _picture;
  static Size _pictureSize = Size.zero;

  ui.Picture _blurredPicture(Size size) {
    final cached = _picture;
    if (cached != null && size == _pictureSize) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rng = Random(7);
    for (var i = 0; i < kBlurredLines; i++) {
      final a = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final b = a +
          Offset(
            (rng.nextDouble() - 0.5) * size.width * 0.12,
            (rng.nextDouble() - 0.5) * size.height * 0.12,
          );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = HSVColor.fromAHSV(
            1,
            i * 360 / kBlurredLines,
            0.65,
            0.95,
          ).toColor()
          ..strokeWidth = 3.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    _pictureSize = size;
    return _picture = recorder.endRecording();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final picture = _blurredPicture(size);

    for (var i = 0; i < kLayersPerFrame; i++) {
      final p = t * 0.9 + i * 0.7;
      // Bounds change every frame, so the offscreen render target is a
      // different size each time rather than being reused.
      final rect = Rect.fromCenter(
        center: Offset(
          size.width * (0.5 + 0.30 * cos(p * 0.6)),
          size.height * (0.5 + 0.30 * sin(p * 0.5)),
        ),
        width: size.width * (0.18 + 0.30 * (0.5 + 0.5 * sin(p))),
        height: size.height * (0.12 + 0.26 * (0.5 + 0.5 * cos(p * 1.3))),
      );

      canvas
        ..saveLayer(rect, Paint()..color = Colors.white.withValues(alpha: 0.85))
        ..drawPicture(picture)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.t != t;
}
