import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_water/src/rain.dart';
import 'package:flame_water/src/rain_drops.dart';

/// The rain's veils ([Rain.veils]): rain so far off that each drop is a fine
/// faint streak, and the air before what stands there turns pale.
///
/// Each veil is three draws: the haze over the view, the streaks through
/// the veil shader (`shaders/veil.frag`, which works every streak out from
/// a formula - nothing of them lives on the CPU), and at the nearest veil
/// in heavy rain the spray the drops kick up along the ground. Load the
/// shader with [load] before the scene is shown; until it is loaded, a veil
/// is its haze and spray.
class RainVeil {
  static FragmentProgram? _program;
  static bool _asked = false;
  static final Expando<FragmentShader> _shaderOf = Expando();

  /// Loads the veil shader. [asset] is the key the app bundles it under; the
  /// package's own tests, where it is the app, pass `shaders/veil.frag`.
  static Future<void> load({
    String asset = 'packages/flame_water/shaders/veil.frag',
  }) async {
    _asked = true;
    _program ??= await FragmentProgram.fromAsset(asset);
  }

  /// The most streaks a veil shows over the view: the look the veils were
  /// tuned to, when each was a line drawn on the CPU.
  static const double maxStreaks = 1600;

  /// Streaks a column of the shader holds.
  static const int _perColumn = 3;

  /// Floats of its uniforms.
  static const int _floats = 5 * 4;

  double _time = 0;
  double _slope = 0;
  final Vector2 _at = Vector2.zero();
  final Vector2 _air = Vector2.zero();
  final Float32List _uniforms = Float32List(_floats);
  final Paint _streaks = Paint();
  final Paint _spray = Paint();

  /// Moves the veils on by [dt]; their slant eases after the wind over
  /// [view], so a gust sweeps through them rather than snapping them.
  void update(Rain rain, Rect view, double dt) {
    _time += dt;
    final fall = RainDrops.terminalSpeed(2);
    final air = rain.windAt;
    var windX = rain.wind.x;
    if (air != null) {
      air(_at..setValues(view.center.dx, view.center.dy), _air);
      windX = _air.x;
    }
    final target = (windX / fall).clamp(-3.0, 3.0);
    _slope += (target - _slope) * (1 - math.exp(-dt / 0.4));
  }

  /// Draws the veil at [depth] of [rain] over [view]; [nearest] when it is
  /// the nearest veil, which the spray rises in front of.
  void render(
    Canvas canvas,
    Rain rain,
    Rect view,
    StreetProjection projection,
    double depth, {
    required bool nearest,
  }) {
    final intensity = rain.intensity.clamp(0.0, 2.5);
    if (intensity <= 0.01) {
      return;
    }
    final metre = rain.metre;
    final color = rain.color;
    final scale = projection.scaleAt(depth);
    // The air before it - the haze - is the air's (`AirVeil`), not the
    // rain's: the rain's own share of it is in the air's extinction.
    final program = _program;
    if (program == null && !_asked) {
      // Loaded on first use if the game did not; the streaks show once it
      // is in.
      load().ignore();
    }
    if (program != null) {
      _drawStreaks(canvas, program, rain, view, scale, depth, intensity);
    }

    // Heavy rain bursting on the ground throws up a low mist along it.
    if (nearest) {
      final spray = (0.35 * (intensity - 0.8)).clamp(0.0, 0.35);
      if (spray > 0) {
        // Along the street line, a metre at a time where hills raise it.
        final level = projection.lift.isLevel;
        final step = level ? view.width + 2 * metre : metre;
        for (var x = view.left - metre; x < view.right + metre; x += step) {
          final line = projection.lineAt(x + step / 2);
          final top = line - 0.7 * metre;
          _spray.shader = Gradient.linear(Offset(0, line), Offset(0, top), [
            color.withValues(alpha: color.a * spray),
            color.withValues(alpha: 0),
          ]);
          canvas.drawRect(Rect.fromLTRB(x, top, x + step, line), _spray);
        }
      }
    }
  }

  void _drawStreaks(
    Canvas canvas,
    FragmentProgram program,
    Rain rain,
    Rect view,
    double scale,
    double depth,
    double intensity,
  ) {
    final metre = rain.metre;
    final color = rain.color;
    // At full rain (2.5) as many streaks a metre as veilDensity says, more
    // the farther off (they cover more air); as hard as it rains, that
    // share of them.
    final perUnit = rain.veilDensity * 2.5 / (metre * scale);
    final transform = canvas.getTransform();
    final pixels = math.sqrt(
      transform[0] * transform[0] + transform[1] * transform[1],
    );
    final alpha = color.a * 0.4 * math.sqrt(scale);
    final f = _uniforms
      ..[0] = view.left
      ..[1] = view.top
      ..[2] = view.width
      ..[3] = view.height
      ..[4] = _time
      ..[5] = RainDrops.terminalSpeed(2) * metre * scale
      ..[6] = 0.34 * scale * metre
      ..[7] = 0.018 * scale * metre
      ..[8] = _slope
      // A veil slides by in the view as anything at its depth does: as
      // much slower than the street as it is smaller.
      ..[9] = view.center.dx * scale
      ..[10] = _perColumn / perUnit
      ..[11] = math.min(
        intensity / 2.5,
        maxStreaks / (perUnit * view.width + _perColumn),
      )
      ..[12] = color.r * alpha
      ..[13] = color.g * alpha
      ..[14] = color.b * alpha
      ..[15] = alpha
      ..[16] = pixels <= 0 ? 1 : 1 / pixels
      ..[17] = depth * 97;
    // A draw takes a copy of the uniforms: one shader serves every veil.
    final shader = _shaderOf[program] ??= program.fragmentShader();
    for (var i = 0; i < _floats; i++) {
      shader.setFloat(i, f[i]);
    }
    canvas.drawRect(view, _streaks..shader = shader);
  }
}
