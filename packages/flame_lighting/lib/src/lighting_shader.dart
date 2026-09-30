import 'dart:ui';

/// The shader that lays a light's pool on the ground, shared by every
/// lighting. Load it once, before the scene is shown; until it is loaded,
/// pools are drawn as soft ovals.
abstract final class LightingShader {
  static FragmentProgram? _program;

  /// The loaded program; `null` before [load] finishes.
  static FragmentProgram? get program => _program;

  /// Loads the program. [asset] is the key the app bundles it under; the
  /// package's own tests, where it is the app, pass `shaders/pool.frag`.
  static Future<void> load({
    String asset = 'packages/flame_lighting/shaders/pool.frag',
  }) async {
    _program ??= await FragmentProgram.fromAsset(asset);
  }
}
