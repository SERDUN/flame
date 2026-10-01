import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where a light is drawn by [LightShader].
enum LightPlane {
  /// What stands on the street line: house fronts, the air before them.
  wall,

  /// The ground band, its rows at the projection's depths.
  ground,
}

/// The shader every light is drawn with (`shaders/light.frag`): one light on
/// one plane, its shape, falloff and cone, cut by what stands in its way.
///
/// Its uniforms are one array of vec4, named in the shader by `#define`;
/// [write] fills them in the same order. Load it once before the scene is
/// shown; until it is loaded, lights are drawn as plain soft discs.
abstract final class LightShader {
  static FragmentProgram? _program;

  /// The program; `null` before [load] finishes.
  static FragmentProgram? get program => _program;

  static final Expando<FragmentShader> _shaders = Expando();

  /// The one shader every light is drawn with; `null` before [load]
  /// finishes. A draw takes a copy of the uniforms it is given, so one
  /// serves every draw.
  static FragmentShader? get shader {
    final program = _program;
    return program == null
        ? null
        : _shaders[program] ??= program.fragmentShader();
  }

  /// Forgets the program, so lights are drawn as before it was loaded: for
  /// tests of that path.
  @visibleForTesting
  static void reset() => _program = null;

  /// Loads the program from [directory], the key the app bundles it under;
  /// the package's own tests, where it is the app, pass `shaders`.
  static Future<void> load({
    String directory = 'packages/flame_lighting/shaders',
  }) async {
    _program ??= await FragmentProgram.fromAsset('$directory/light.frag');
  }

  /// Capsules the shader takes.
  static const int maxShadows = 8;

  /// Where the capsules start, in vec4s; two vec4 each.
  static const int capsules = 8;

  /// vec4s in the shader's `u` array.
  static const int vectors = capsules + maxShadows * 2;

  // Offsets, in floats: the shader's names. The light's five vec4 come
  // first, as [LightField.writeLight] writes them.
  static const int projectionTop = LightField.lightFloats;
  static const int projectionBand = projectionTop + 1;
  static const int projectionNear = projectionTop + 2;
  static const int projectionFar = projectionTop + 3;
  static const int projectionEye = projectionTop + 4;
  static const int planeMode = projectionTop + 5;
  static const int drawAmount = projectionTop + 6;
  static const int falloffMode = projectionTop + 7;
  static const int shadowCount = projectionTop + 8;

  static final Float32List _floats = Float32List(vectors * 4);

  /// Fills [shader] to draw light [i] of [field] on [plane] at [amount],
  /// with [projection] and [shadows].
  static void write(
    FragmentShader shader,
    LightField field,
    int i, {
    required LightPlane plane,
    required double amount,
    StreetProjection? projection,
    ShadowSet? shadows,
  }) {
    final f = _floats..fillRange(0, _floats.length, 0);
    field.writeLight(i, f, 0);
    if (projection != null) {
      projection.writeUniforms(f, projectionTop);
    } else {
      // No street: a flat far wall, the ground never asked for.
      f
        ..[projectionBand] = 1
        ..[projectionNear] = 1
        ..[projectionFar] = 2;
    }
    f
      ..[planeMode] = plane == LightPlane.ground ? 1 : 0
      ..[drawAmount] = amount
      ..[falloffMode] = field.isPhysicalOf(i) ? 1 : 0;
    if (shadows != null) {
      final n = shadows.count < maxShadows ? shadows.count : maxShadows;
      f
        ..[shadowCount] = n.toDouble()
        ..setRange(
          capsules * 4,
          capsules * 4 + n * ShadowSet.stride,
          shadows.data,
        );
    }
    for (var k = 0; k < f.length; k++) {
      shader.setFloat(k, f[k]);
    }
  }
}
