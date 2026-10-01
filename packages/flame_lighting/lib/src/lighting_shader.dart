import 'dart:ui';

/// The shaders the lighting draws with, shared by every lighting: a light's
/// cone, and the pool it lays on the ground. Load them once, before the
/// scene is shown; until they are loaded, cones are drawn through a layer
/// and pools as soft ovals.
abstract final class LightingShader {
  static FragmentProgram? _pool;
  static FragmentProgram? _cone;

  /// The pool program; `null` before [load] finishes.
  static FragmentProgram? get program => _pool;

  /// The cone program; `null` before [load] finishes.
  static FragmentProgram? get cone => _cone;

  /// Loads the programs from [directory], the key the app bundles them
  /// under; the package's own tests, where it is the app, pass `shaders`.
  static Future<void> load({
    String directory = 'packages/flame_lighting/shaders',
  }) async {
    _pool ??= await FragmentProgram.fromAsset('$directory/pool.frag');
    _cone ??= await FragmentProgram.fromAsset('$directory/light.frag');
  }
}
