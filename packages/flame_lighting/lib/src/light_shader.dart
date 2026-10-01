import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';

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
  static const int capsules = 7;

  /// vec4s in the shader's `u` array.
  static const int vectors = capsules + maxShadows * 2;

  // Offsets, in floats: the shader's names. The light's four vec4 come
  // first, as [LightField.writeLight] writes them.
  static const int projectionTop = 16;
  static const int projectionBand = 17;
  static const int projectionNear = 18;
  static const int projectionFar = 19;
  static const int projectionEye = 20;
  static const int planeMode = 21;
  static const int drawAmount = 22;
  static const int falloffMode = 23;
  static const int shadowCount = 24;

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
