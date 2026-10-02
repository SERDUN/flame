import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame_lighting/src/light_buffer_none.dart'
    if (dart.library.ffi) 'package:flame_lighting/src/light_buffer_gpu.dart'
    as impl;
import 'package:flame_stage/flame_stage.dart';

/// Every light of a frame added up once, on the GPU, into a float image of
/// the view: in each pixel the light cast there (rgb, brighter than white
/// where it is) and what glows there itself, as white light (a).
///
/// It is the lighting's fast path: one pass for all the lights, where the
/// canvas path draws each light on each plane, twice. The lighting then
/// lays the night and the light cast over the scene from it in two draws,
/// and a wet wall's sheen is one draw that reads it.
///
/// It runs on flutter_gpu, so only where that is on (Impeller, with the
/// app's `FLTEnableFlutterGPU` / `io.flutter.embedding.android.EnableFlutterGPU`
/// flag): [create] gives null elsewhere - the web, a test - and the lighting
/// keeps to the canvas.
abstract class LightBuffer {
  /// A buffer, or null where there is no flutter_gpu to run it on.
  static Future<LightBuffer?> create() => impl.createLightBuffer();

  /// Whether a buffer can be made at all; known after the first [create].
  static bool? get available => impl.lightBufferAvailable;

  /// Lights it adds up at once: the strongest that reach the view.
  static const int maxLights = 16;

  /// Capsules of shadow it takes.
  static const int maxShadows = 24;

  /// Floats of its parameters (`Params` in light_buffer.frag).
  static const int floats = 4 * (4 + maxLights * 5 + maxShadows * 2);

  /// Where the lights start, in floats.
  static const int lightsAt = 16;

  /// Adds up [frame]'s lights over [area] (world) into an image [width] by
  /// [height] pixels: (r, g, b) the light cast, a what glows itself. Above
  /// the street line the light falls on a wall plane [wallAhead] in front of
  /// the line (behind it, negative: a far layer's). Each [slot] keeps its
  /// own image; another slot's render leaves it be.
  ui.Image? render(
    StageFrame frame,
    ui.Rect area,
    int width,
    int height, {
    double wallAhead = 0,
    int slot = 0,
  });

  void dispose();

  /// Writes [frame]'s parameters over [area] into [into]: the area, the
  /// street, the lights - the strongest [maxLights] that reach the area -
  /// the shadows, and the eye's exposure.
  static void write(
    Float32List into,
    StageFrame frame,
    ui.Rect area, {
    double wallAhead = 0,
  }) {
    into.fillRange(0, into.length, 0);
    final field = frame.light;
    final projection = frame.projection;
    into
      ..[0] = area.left
      ..[1] = area.top
      ..[2] = area.width
      ..[3] = area.height;
    if (projection != null) {
      into
        ..[4] = projection.band.top
        ..[5] = projection.band.height
        ..[6] = projection.nearDistance
        ..[7] = projection.farDistance
        ..[8] = projection.eyeHeight;
    } else {
      // No street: a wall plane only.
      into
        ..[6] = 1
        ..[7] = 2;
    }
    final picked = _picked..clear();
    for (var i = 0; i < field.count; i++) {
      final r = field.reachOf(i) + field.haloRadiusOf(i);
      final x = field.xOf(i);
      final y = field.yOf(i);
      final ex = math.max(field.extentXOf(i), field.extentYOf(i));
      if (x + r + ex < area.left ||
          x - r - ex > area.right ||
          y + r + ex < area.top ||
          y - r - ex > area.bottom) {
        continue;
      }
      picked.add(i);
    }
    if (picked.length > maxLights) {
      picked.sort((a, b) => field.strengthOf(b).compareTo(field.strengthOf(a)));
    }
    final n = math.min(picked.length, maxLights);
    for (var k = 0; k < n; k++) {
      field.writeLight(picked[k], into, lightsAt + k * LightField.lightFloats);
    }
    final shadows = frame.shadows;
    final capsules = math.min(shadows.count, maxShadows);
    into
      ..[9] = n.toDouble()
      ..[10] = capsules.toDouble()
      ..[11] = field.haze
      ..[12] = field.exposure
      ..[13] = wallAhead
      ..setRange(
        lightsAt + maxLights * LightField.lightFloats,
        lightsAt +
            maxLights * LightField.lightFloats +
            capsules * ShadowSet.stride,
        shadows.data,
      );
  }

  static final List<int> _picked = [];
}
