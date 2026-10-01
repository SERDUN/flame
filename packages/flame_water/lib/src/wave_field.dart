import 'dart:ui' as ui;

import 'package:flame_water/src/wave_field_none.dart'
    if (dart.library.ffi) 'package:flame_water/src/wave_field_gpu.dart'
    as impl;

/// A water surface's heights, moved by the wave equation on the GPU: drops
/// push it down where they land, and the rings spread, cross and reflect off
/// the edges as water's do.
///
/// It runs on flutter_gpu, so only where that is on (Impeller, with the app's
/// `FLTEnableFlutterGPU` / `io.flutter.embedding.android.EnableFlutterGPU`
/// flag): [create] gives null elsewhere - the web, a test - and the water
/// keeps to its rings.
abstract class WaveField {
  /// A field of [columns] by [rows] square cells, or null where there is no
  /// flutter_gpu to run it on.
  static Future<WaveField?> create({required int columns, required int rows}) =>
      impl.createWaveField(columns, rows);

  /// Whether a field can be made at all; known after the first [create].
  static bool? get available => impl.waveFieldAvailable;

  int get columns;
  int get rows;

  /// A drop landing at [u], [v] (0..1 across and down the field), pushing
  /// the surface down by [depth] under it, over [radius] cells.
  void drop(
    double u,
    double v, {
    required double radius,
    required double depth,
  });

  /// Moves the surface on by [steps] steps of the wave equation; each step
  /// keeps [damping] of the motion.
  void step(int steps, {required double damping});

  /// The heights now, one float a cell in the red channel, for a dart:ui
  /// shader to sample (unfiltered: not every GPU filters float textures).
  ui.Image? get heights;

  void dispose();
}

/// Keeps [keep] of the drops waiting in [drops] (u, v, radius, depth each),
/// spread evenly over them, each taking on the depth of those left out
/// beside it: as much rain strikes the surface, in fewer places.
void thinDrops(List<double> drops, int keep) {
  final count = drops.length ~/ 4;
  if (count <= keep) {
    return;
  }
  if (keep <= 0) {
    drops.clear();
    return;
  }
  final weight = count / keep;
  for (var i = 0; i < keep; i++) {
    final from = (i * weight).floor() * 4;
    drops
      ..[i * 4] = drops[from]
      ..[i * 4 + 1] = drops[from + 1]
      ..[i * 4 + 2] = drops[from + 2]
      ..[i * 4 + 3] = drops[from + 3] * weight;
  }
  drops.removeRange(keep * 4, drops.length);
}
