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
        mirror,
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
      // In thin horizontal slices, each moved as the water under it moves:
      // a ring passing through the mirrored lamp tears it apart.
      const slices = 7;
      final slice = coreRadius * 2 / slices;
      for (var s = 0; s < slices; s++) {
        final y = center.dy - coreRadius + s * slice;
        final shift = mirror.disturbanceAt(center.dx, y + slice / 2);
        canvas
          ..save()
          ..clipRect(
            Rect.fromLTRB(
              center.dx - coreRadius * 2,
              y,
              center.dx + coreRadius * 2,
              y + slice + 0.5,
            ),
          )
          ..translate(shift.dx, shift.dy)
          ..drawCircle(center, coreRadius, paint)
          ..restore();
      }
    }
    canvas.restore();
  }

  /// The glow of a mirrored light, from [top] to [bottom] round [center]:
  /// a narrow soft column a few sources wide, and over it bright slivers,
  /// broken the way a wet surface breaks a reflection - uneven gaps and
  /// heights, set a little off the axis, each coming and going on its own
  /// in time. Brightest at the mirrored source, fading [tall] above and
  /// below it. [width] is how wide the column may get.
  void _drawSlivers(
    Canvas canvas,
    Paint paint,
    LightMirror mirror,
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
    final from = math.max(top, center.dy - tall);
    final to = math.min(bottom, center.dy + tall);
    if (to <= from) {
      return;
    }
    // A source as small as nothing still leaves a thin streak.
    final source = math.max(light.sourceRadius, 2.0);
    final column = math.min(width, source * 4);

    // The soft column under the slivers: one narrow tall glow.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.radial(
        Offset.zero,
        column,
        [
          light.color.withValues(alpha: alpha * 0.45),
          light.color.withValues(alpha: 0),
        ],
      );
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(1, tall / column)
      ..drawCircle(Offset.zero, column, paint)
      ..restore();

    paint
      ..shader = null
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    var y = from;
    var k = 0;
    while (y < to) {
      final h0 = _hash(seed + k * 3.1);
      final h1 = _hash(seed + k * 5.7 + 11);
      final h2 = _hash(seed + k * 9.3 + 23);
      k++;
      final along = 1 - ((y - center.dy).abs() / tall).clamp(0.0, 1.0);
      // Each sliver comes and goes on its own slow beat.
      final beat = 0.5 + 0.5 * math.sin(_time * (1.5 + 2.5 * h0) + h1 * 6.3);
      final height = 1.2 + 2.2 * h2;
      if (beat > 0.25) {
        final half =
            column *
            (0.25 + 0.75 * along) *
            (0.4 + 0.6 * h1) *
            (0.6 + 0.4 * beat);
        final drift =
            (h0 - 0.5) * column * (1 - along) * 1.2 +
            math.sin(_time * 1.9 + h2 * 6.3) * source * 0.5;
        // The water moves under the sliver: a ring passing shoves it
        // aside, and where the surface tilts it catches more of the light.
        final x = center.dx + drift;
        final shift = mirror.disturbanceAt(x, y + height / 2);
        final tilt = math.min(shift.distance / source, 1.0);
        final a =
            alpha *
            along *
            (0.3 + 0.7 * beat) *
            (0.5 + 0.5 * h2) *
            (1 + 0.8 * tilt);
        if (a > 0.01 && half >= 0.5) {
          paint.color = light.color.withValues(alpha: a.clamp(0.0, 1.0));
          canvas.drawRect(
            Rect.fromLTRB(
              x + shift.dx * 2 - half,
              y + shift.dy,
              x + shift.dx * 2 + half,
              y + shift.dy + height,
            ),
            paint,
          );
        }
      }
      // Uneven gaps: tight near the source, looser away from it.
      y += height + 1.5 + (2 + 6 * h0) * (1.3 - along);
    }
    // The paint is shared: its colour's alpha would dim every gradient drawn
    // with it after this.
    paint
      ..maskFilter = null
      ..color = const Color(0xFFFFFFFF);
  }

  /// A steady pseudo-random number in `0..1` for [x].
  static double _hash(double x) {
    final s = math.sin(x * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }
}
