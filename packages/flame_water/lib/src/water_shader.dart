import 'dart:ui';

/// The shader that bends a reflection around the rings on the water, shared
/// by every surface. Load it once, before the water is shown (on the web it
/// compiles at load): until it is loaded, surfaces draw a plain mirror.
abstract final class WaterShader {
  static FragmentProgram? _program;

  /// Rings one surface bends its reflection with at a time: the newest ones.
  static const int maxRings = 16;

  /// The loaded program; `null` before [load] finishes.
  static FragmentProgram? get program => _program;

  /// Loads the program. [asset] is the key the app bundles it under; the
  /// package's own tests, where it is the app, pass `shaders/water.frag`.
  static Future<void> load({
    String asset = 'packages/flame_water/shaders/water.frag',
  }) async {
    _program ??= await FragmentProgram.fromAsset(asset);
  }
}
