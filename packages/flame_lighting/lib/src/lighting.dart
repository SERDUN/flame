import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/light_mirror.dart';
import 'package:flame_lighting/src/light_source.dart';

/// The night over a world, and its lights.
///
/// Drawn over everything below its priority: the view is covered with
/// [ambient] at [darkness], every [LightSource] cuts its shape out of that
/// dark with a soft falloff, and then adds its colour on top at [glow] - so a
/// lamp both reveals the street under it and warms it. A [LightMirror]
/// (water, a wet road) gives back the lights above it: each one mirrored
/// about the surface's line, drawn out down it into a streak, clipped to it.
///
/// Only blend modes and gradients: no shader, no offscreen image beyond one
/// layer, so it works on every renderer, the web included.
///
/// Components drawn above it (a higher priority) are not darkened: rain that
/// should shine in the lamps' light can draw itself there, as bright as
/// [lightAt] says.
class Lighting extends Component {
  Lighting({
    this.ambient = const Color(0xFF060A16),
    this.darkness = 0.65,
    this.glow = 0.35,
    this.haze = 0.4,
    super.priority = 1000,
  });

  /// The colour of the night.
  Color ambient;

  /// How dark it is where no light falls, `0..1`: 0 day, 1 black night.
  double darkness;

  /// How much colour the lights add over what they reveal, `0..1`.
  double glow;

  /// How thick the air is with rain and mist, `0..1`: it scatters every
  /// light into a wide soft halo round its source, as a lamp in a wet night
  /// glows far beyond its bulb.
  double haze;

  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  final Paint _layer = Paint();
  final Paint _dark = Paint();
  final Paint _cut = Paint()..blendMode = BlendMode.dstOut;
  final Paint _add = Paint()..blendMode = BlendMode.plus;
  final Paint _coneLayer = Paint();
  final Paint _fill = Paint();
  final Paint _coneMask = Paint()..blendMode = BlendMode.dstIn;

  Iterable<LightSource> get _lights =>
      _world().descendants().whereType<LightSource>();

  Iterable<LightMirror> get _mirrors =>
      _world().descendants().whereType<LightMirror>();

  Component _world() {
    Component top = this;
    for (final a in ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top;
  }

  /// How lit [point] is (world coordinates): the ambient share that is left
  /// of the night plus every light reaching it, and the colour the lights
  /// give it there.
  ({double light, Color color}) lightAt(Vector2 point) {
    var total = 0.0;
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    for (final light in _lights) {
      final amount = light.lightAt(point);
      if (amount <= 0) {
        continue;
      }
      total += amount;
      r += light.color.r * amount;
      g += light.color.g * amount;
      b += light.color.b * amount;
    }
    final base = 1 - darkness;
    if (total <= 0) {
      return (light: base, color: const Color(0xFFFFFFFF));
    }
    return (
      light: (base + total).clamp(0.0, 1.0),
      color: Color.from(
        alpha: 1,
        red: r / total,
        green: g / total,
        blue: b / total,
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final view = CameraComponent.currentCamera?.visibleWorldRect.inflate(4);
    if (view == null) {
      return;
    }
    final lights = _lights.toList();
    final mirrors = _mirrors.toList();

    canvas.saveLayer(view, _layer);
    canvas.drawRect(
      view,
      _dark..color = ambient.withValues(alpha: darkness.clamp(0.0, 1.0)),
    );
    for (final light in lights) {
      _drawLight(canvas, light, _cut, 1, light.strength.clamp(0.0, 1.0));
      _drawHalo(canvas, light, _cut, 1);
    }
    for (final mirror in mirrors) {
      _drawMirrored(canvas, mirror, lights, _cut, 1);
    }
    canvas.restore();

    if (glow <= 0) {
      return;
    }
    for (final light in lights) {
      _drawLight(canvas, light, _add, glow, light.strength);
      _drawHalo(canvas, light, _add, glow);
    }
    for (final mirror in mirrors) {
      _drawMirrored(canvas, mirror, lights, _add, glow);
    }
  }

  /// The light scattered by the air round [light]'s source: a wide soft
  /// halo, as big and as bright as [haze] makes it.
  void _drawHalo(Canvas canvas, LightSource light, Paint paint, double amount) {
    final a = (amount * haze * light.strength * 0.6).clamp(0.0, 1.0);
    if (a <= 0 || light.sourceRadius <= 0) {
      return;
    }
    final center = light.absolutePosition.toOffset();
    final radius = light.sourceRadius * (6 + 24 * haze);
    paint.shader = Gradient.radial(
      center,
      radius,
      [
        light.color.withValues(alpha: a),
        light.color.withValues(alpha: a * 0.35),
        light.color.withValues(alpha: 0),
      ],
      const [0, 0.25, 1],
    );
    canvas.drawCircle(center, radius, paint);
  }

  /// [light]'s shape filled with its colour fading out from its centre, at
  /// [amount] times its [strength], with [paint]'s blend mode.
  void _drawLight(
    Canvas canvas,
    LightSource light,
    Paint paint,
    double amount,
    double strength,
  ) {
    final a = (amount * strength).clamp(0.0, 1.0);
    if (a <= 0) {
      return;
    }
    final center = light.absolutePosition.toOffset();
    final falloff = Gradient.radial(
      center,
      light.radius,
      [
        light.color.withValues(alpha: a),
        light.color.withValues(alpha: a * 0.35),
        light.color.withValues(alpha: 0),
      ],
      const [0, 0.35, 1],
    );
    final cone = light.coneAngle;
    if (cone == null) {
      paint.shader = falloff;
      canvas.drawCircle(center, light.radius, paint);
      return;
    }
    // A cone with no hard edge: the disc of light, masked across by a sweep
    // that is full along the axis and eases out to both sides. Done in a
    // layer, which lands on the night with the light's own blend mode.
    final bounds = Rect.fromCircle(center: center, radius: light.radius);
    final half = cone / 2;
    const soft = LightSource.softEdge / 2;
    canvas
      ..saveLayer(bounds, _coneLayer..blendMode = paint.blendMode)
      ..drawCircle(center, light.radius, _fill..shader = falloff)
      ..save()
      ..translate(center.dx, center.dy)
      // Turned so the cone points along pi: its sweep never wraps past 0.
      ..rotate(light.coneDirection - math.pi);
    _coneMask.shader = Gradient.sweep(
      Offset.zero,
      const [
        Color(0x00FFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
      ],
      const [0, soft, 1 - soft, 1],
      TileMode.decal,
      math.pi - half,
      math.pi + half,
    );
    canvas
      ..drawCircle(Offset.zero, light.radius, _coneMask)
      ..restore()
      ..restore();
  }

  /// How much more a surface gives back of a light seen low across it than
  /// its [LightMirror.mirrorStrength] says: water seen at a grazing angle
  /// mirrors most of what falls on it (Fresnel), so a puddle shows a lamp
  /// nearly as bright as the lamp.
  static const double grazing = 1.6;

  /// The lights above [mirror] as it shows them, each mirrored about its
  /// line and squeezed, clipped to it: the light's own source as a bright
  /// core nearly as strong as the source - a mirror image of a lamp is a
  /// lamp - and its glow as a column of short horizontal slivers running
  /// down the surface, each flickering in width and brightness: the surface
  /// is never flat, so the reflection breaks into pieces that shimmer, as a
  /// lamp's does on a wet road. The core ignores [amount]: it is the light
  /// itself, not its glow.
  void _drawMirrored(
    Canvas canvas,
    LightMirror mirror,
    List<LightSource> lights,
    Paint paint,
    double amount,
  ) {
    final reflect = (mirror.mirrorStrength * grazing).clamp(0.0, 1.0);
    if (reflect <= 0) {
      return;
    }
    final clip = mirror.mirrorClip();
    final bounds = clip.getBounds();
    canvas
      ..save()
      ..clipPath(clip);
    for (final (index, light) in lights.indexed) {
      final at = light.absolutePosition;
      final height = mirror.mirrorLine - at.y;
      if (height <= 0) {
        continue;
      }
      final width = light.radius * 0.35;
      if (at.x + width < bounds.left || at.x - width > bounds.right) {
        continue;
      }
      final strength = light.strength.clamp(0.0, 1.0);
      final center = Offset(
        at.x,
        mirror.mirrorLine + height * mirror.mirrorSquash,
      );
      _drawSlivers(
        canvas,
        paint,
        light,
        center,
        width,
        tall: width * mirror.mirrorStretch,
        top: math.max(mirror.mirrorLine, bounds.top),
        bottom: bounds.bottom,
        alpha: (amount * reflect * strength).clamp(0.0, 1.0),
        seed: index * 7.31,
      );
      final core = reflect * strength;
      final coreRadius = light.sourceRadius * 2.5;
      paint
        ..maskFilter = null
        ..shader = Gradient.radial(
          center,
          coreRadius,
          [
            Color.lerp(
              light.color,
              const Color(0xFFFFFFFF),
              0.5,
            )!.withValues(alpha: core),
            light.color.withValues(alpha: core * 0.6),
            light.color.withValues(alpha: 0),
          ],
          const [0, 0.35, 1],
        );
      canvas.drawCircle(center, coreRadius, paint);
    }
    canvas.restore();
  }

  /// Gap between the slivers of a broken reflection, and their height.
  static const double _sliverGap = 5;
  static const double _sliverHeight = 2.2;

  /// The glow of a mirrored light as slivers from [top] to [bottom] round
  /// [center]: brightest at the mirrored source and fading [tall] above and
  /// below it, [width] across at most, each sliver's width and brightness
  /// wavering on its own in time.
  void _drawSlivers(
    Canvas canvas,
    Paint paint,
    LightSource light,
    Offset center,
    double width, {
    required double tall,
    required double top,
    required double bottom,
    required double alpha,
    required double seed,
  }) {
    if (alpha <= 0 || tall <= 0) {
      return;
    }
    paint
      ..shader = null
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final from = math.max(top, center.dy - tall);
    final to = math.min(bottom, center.dy + tall);
    for (var y = from; y < to; y += _sliverGap) {
      final i = (y - from) / _sliverGap + seed;
      final along = 1 - ((y - center.dy).abs() / tall).clamp(0.0, 1.0);
      // Two slow waves per sliver, out of step with its neighbours.
      final waver =
          0.5 +
          0.3 * math.sin(_time * 2.3 + i * 1.7) +
          0.2 * math.sin(_time * 3.7 + i * 0.6);
      final half = width * (0.15 + 0.55 * along) * (0.6 + 0.4 * waver);
      final a = alpha * along * along * (0.35 + 0.65 * waver);
      if (a <= 0.01 || half < 0.5) {
        continue;
      }
      paint.color = light.color.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromLTRB(
          center.dx - half,
          y,
          center.dx + half,
          y + _sliverHeight,
        ),
        paint,
      );
    }
    // The paint is shared: its colour's alpha would dim every gradient drawn
    // with it after this.
    paint
      ..maskFilter = null
      ..color = const Color(0xFFFFFFFF);
  }
}
