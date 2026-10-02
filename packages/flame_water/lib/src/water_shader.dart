import 'dart:typed_data';
import 'dart:ui';

/// The water shader (`shaders/water.frag`), shared by every surface, and the
/// layout of its uniforms.
///
/// Its uniforms are one array of vec4, named in the shader by `#define`;
/// the offsets here are the same names, so the two are read side by side.
/// Load it once, before the water is shown (on the web it compiles at
/// load): until it is loaded, surfaces draw a plain mirror.
abstract final class WaterShader {
  static FragmentProgram? _program;

  /// Rings one surface bends its reflection with at a time: the newest ones.
  static const int maxRings = 32;

  /// Lights one surface mirrors at a time: the strongest.
  static const int maxLights = 8;

  /// vec4s before the rings.
  static const int header = 12;

  /// Floats per mirrored light: six vec4.
  static const int lightFloats = 24;

  /// Where the rings start, in floats.
  static const int rings = header * 4;

  /// Where the lights start, in floats.
  static const int lights = rings + maxRings * 4;

  /// Floats in the array.
  static const int floats = lights + maxLights * lightFloats;

  // Header offsets, in floats: the shader's names.
  static const int size = 0;
  static const int count = 2;
  static const int flatten = 3;
  static const int wavelength = 4;
  static const int gain = 5;
  static const int time = 6;
  static const int chop = 7;
  static const int elevTop = 8;
  static const int elevBottom = 9;
  static const int fresnel = 10;
  static const int spread = 11;
  static const int base = 12;
  static const int tint = 16;
  static const int fade = 20;
  static const int line = 21;
  static const int pool = 22;
  static const int poolHalf = 24;
  static const int soft = 26;
  static const int round = 27;
  static const int pixels = 28;
  static const int lightMode = 29;
  static const int lightCount = 30;
  static const int haze = 31;
  static const int wave = 32;
  static const int glint = 36;
  static const int squash = 41;
  static const int air = 42;
  static const int airMap = 43;
  static const int image = 44;

  /// The loaded program; `null` before [load] finishes.
  static FragmentProgram? get program => _program;

  static final Expando<FragmentShader> _shaders = Expando();

  /// The one shader every surface draws [program] with: a draw takes a copy
  /// of the uniforms and images it is given, so one serves them all.
  static FragmentShader shaderOf(FragmentProgram program) =>
      _shaders[program] ??= program.fragmentShader();

  /// Loads the program. [asset] is the key the app bundles it under; the
  /// package's own tests, where it is the app, pass `shaders/water.frag`.
  static Future<void> load({
    String asset = 'packages/flame_water/shaders/water.frag',
  }) async {
    _program ??= await FragmentProgram.fromAsset(asset);
  }

  /// Writes [c] premultiplied at [at].
  static void color(Float32List into, int at, Color c) {
    into
      ..[at] = c.r * c.a
      ..[at + 1] = c.g * c.a
      ..[at + 2] = c.b * c.a
      ..[at + 3] = c.a;
  }

  /// Sets every float of [values] on [shader], in order.
  static void upload(FragmentShader shader, Float32List values) {
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
  }
}
