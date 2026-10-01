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

  /// Moves the surface on by [steps] steps of the wave equation; in each a
  /// wave travels [courant] cells (no more than 1/sqrt(2)), and [damping] of
  /// the motion is kept.
  void step(int steps, {required double damping, required double courant});

  /// The heights now, one float a cell in the red channel, for a dart:ui
  /// shader to sample (unfiltered: not every GPU filters float textures).
  ui.Image? get heights;

  /// Lets go of the field's textures; it is not used after.
  void dispose();
}
