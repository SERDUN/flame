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
  static void reset() {
    _program = null;
    _compose = null;
    _air = null;
  }

  /// Loads the program from [directory], the key the app bundles it under;
  /// the package's own tests, where it is the app, pass `shaders`.
  static Future<void> load({
    String directory = 'packages/flame_lighting/shaders',
  }) async {
    _program ??= await FragmentProgram.fromAsset('$directory/light.frag');
    _compose ??= await FragmentProgram.fromAsset(
      '$directory/light_compose.frag',
    );
    _air ??= await FragmentProgram.fromAsset('$directory/air.frag');
  }

  static FragmentProgram? _air;

  /// The shader the air is laid over what is drawn with
  /// (`shaders/air.frag`, `AirVeil`); `null` before [load] finishes.
  static FragmentShader? get air {
    final program = _air;
    return program == null
        ? null
        : _shaders[program] ??= program.fragmentShader();
  }

  static FragmentProgram? _compose;

  /// The shader the light buffer is laid over the scene with
  /// (`shaders/light_compose.frag`); `null` before [load] finishes.
  static FragmentShader? get compose {
    final program = _compose;
    return program == null
        ? null
        : _shaders[program] ??= program.fragmentShader();
  }

  /// Capsules the shader takes.
  static const int maxShadows = 24;

  /// Where the capsules start, in vec4s; two vec4 each.
  static const int capsules = 8;

  /// vec4s in the shader's `u` array.
  static const int vectors = capsules + maxShadows * 2 + liftSamples ~/ 4 + 1;

  /// Samples of the ground's height across the band, and where they start
  /// in floats; the band's span after them.
  static const int liftSamples = 32;
  static const int liftAt = (capsules + maxShadows * 2) * 4;
  static const int liftSpanAt = liftAt + liftSamples;

  // Offsets, in floats: the shader's names. The light's five vec4 come
  // first, as [LightField.writeLight] writes them.
  static const int projectionTop = LightField.lightFloats;
  static const int projectionBand = projectionTop + 1;
  static const int projectionNear = projectionTop + 2;
  static const int projectionFar = projectionTop + 3;
  static const int projectionEye = projectionTop + 4;
  static const int planeMode = projectionTop + 5;
  static const int drawAmount = projectionTop + 6;
  static const int wallAhead = projectionTop + 7;
  static const int shadowCount = projectionTop + 8;
  static const int airDepth = projectionTop + 9;
  static const int airVisibility = projectionTop + 10;

  static final Float32List _floats = Float32List(vectors * 4);

  /// Fills [shader] to draw light [i] of [field] on [plane] at [amount],
  /// with [projection] and [shadows]. With [air] the light fills that much
  /// air in front of the plane rather than falling on it: a thing's shadow
  /// in it is as deep as the thing is thick against the air's depth, and a
  /// lamp lights only the air near it, as much as [visibility] (world
  /// units) lets that glow against the whole air's.
  static void write(
    FragmentShader shader,
    LightField field,
    int i, {
    required LightPlane plane,
    required double amount,
    StreetProjection? projection,
    ShadowSet? shadows,
    double wall = 0,
    double air = 0,
    double visibility = 1e9,
  }) {
    final f = _floats..fillRange(0, _floats.length, 0);
    field.writeLight(i, f, 0);
    if (projection != null) {
      projection.writeUniforms(f, projectionTop);
      // The hills across the band; none on level ground.
      if (!projection.lift.isLevel) {
        final band = projection.band;
        projection.writeLift(f, liftAt, band.left, band.right, liftSamples);
        f
          ..[liftSpanAt] = band.left
          ..[liftSpanAt + 1] = band.right
          ..[liftSpanAt + 2] = liftSamples.toDouble();
      }
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
      ..[wallAhead] = wall
      ..[airDepth] = air
      ..[airVisibility] = visibility;
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
