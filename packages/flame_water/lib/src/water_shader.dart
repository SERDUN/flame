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
  static const int header = 19;

  /// Floats per mirrored light: six vec4.
  static const int lightFloats = 24;

  /// Where the rings start, in floats.
  static const int rings = header * 4;

  /// Where the lights start, in floats.
  static const int lights = rings + maxRings * 4;

  /// Other waters lying on one at a time, cut out of it: the nearest.
  static const int maxHoles = 8;

  /// Where the holes start, in floats: one vec4 each, centre and half
  /// extents in the surface's units.
  static const int holes = lights + maxLights * lightFloats;

  /// Where the light the depth glows by starts, in floats: the buffer's
  /// rect ([lampArea]), how it is read ([lampInfo]) and the medium's top
  /// layer ([surface]).
  static const int body = holes + maxHoles * 4;

  /// Samples of the street line across the water: on hills and round a
  /// bend each column is mirrored about the line where it is.
  static const int lineSamples = 32;

  /// Where the street line's samples start, in floats: local y at
  /// [lineSamples] evenly spaced local x, after the medium's top layer.
  static const int lineAt = body + 3 * 4;

  /// Where their span is, in floats: the local x of the first and the
  /// last, and how many (0: one line, [line], level ground).
  static const int lineSpan = lineAt + lineSamples;

  /// Floats in the array.
  static const int floats = lineSpan + 4;

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

  /// 1: the picture read is already smeared up and down by the spread.
  static const int preSmeared = 40;
  static const int squash = 41;
  static const int air = 42;
  static const int airMap = 43;
  static const int image = 44;
  static const int skyTop = 48;
  static const int skyHorizon = 52;
  static const int skyY = 56;
  static const int attenuation = 60;
  static const int depth = 63;
  static const int deep = 64;
  static const int f0 = 67;
  static const int ambient = 68;
  static const int pass = 71;
  static const int holeCount = 72;
  static const int holeSoft = 73;
  static const int darken = 74;

  // After the holes: the light the depth glows by.
  static const int lampArea = body;
  static const int lampInfo = body + 4;

  /// The medium's top layer: what it sends back of the light a beam of
  /// light puts into it (rgb).
  static const int silt = body + 8;

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
