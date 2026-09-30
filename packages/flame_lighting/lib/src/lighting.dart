import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_lighting/src/light_mirror.dart';
import 'package:flame_lighting/src/light_source.dart';

/// The night over a world, and its lights.
///
/// Drawn over everything below its priority, in three passes:
/// - the night: the view covered with [ambient] at [darkness], every
///   [LightSource] cutting its shape out of that dark with a soft falloff;
/// - the light cast: each light's colour added on top at [glow], so a lamp
///   both reveals the street under it and warms it;
/// - the glow: every [Emissive] part of the world (bulbs, lit windows, the
///   halo [haze] makes round them) drawn over the night undimmed, and then
///   given to every [LightMirror] (water, a wet road) to show mirrored as it
///   shows anything - ripples bend it, a rough wet road smears it long;
///   and every [Glossy] surface (a wet wall) glinting where the lights fall
///   on it, with rivulets running down it.
///
/// The night and the light cast are blend modes and gradients in one layer,
/// so they work on every renderer, the web included.
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

  /// The lighting drawing now, for the [Emissive] parts it draws.
  static Lighting? get current => _current;
  static Lighting? _current;

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
    final world = _world();

    canvas.saveLayer(view, _layer);
    canvas.drawRect(
      view,
      _dark..color = ambient.withValues(alpha: darkness.clamp(0.0, 1.0)),
    );
    for (final light in lights) {
      _drawLight(canvas, light, _cut, 1, light.strength.clamp(0.0, 1.0));
    }
    canvas.restore();

    if (glow > 0) {
      for (final light in lights) {
        _drawLight(canvas, light, _add, glow, light.strength);
      }
    }

    _current = this;
    try {
      for (final wet in world.descendants().whereType<Glossy>()) {
        _drawSheen(canvas, wet, lights);
      }
      _renderGlow(world, canvas);
      for (final mirror in _mirrors) {
        mirror.renderMirroredGlow(canvas, (c) => _renderGlow(world, c));
      }
    } finally {
      _current = null;
    }
  }

  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  /// The lights glinting off [wet]: each light's cast once more, over its
  /// wet area only, as strong as it is glossy - and rivulets running down
  /// it, each a thin line as bright as the light where it is, with a
  /// brighter bead of water sliding down.
  void _drawSheen(Canvas canvas, Glossy wet, List<LightSource> lights) {
    final gloss = wet.gloss.clamp(0.0, 1.0);
    if (gloss <= 0) {
      return;
    }
    final area = wet.glossArea();
    final bounds = area.getBounds();
    canvas
      ..save()
      ..clipPath(area);
    for (final light in lights) {
      _drawLight(canvas, light, _add, gloss * 0.45, light.strength);
    }
    final every = 100 / math.max(wet.rivulets, 0.1);
    var i = 0;
    for (var x = bounds.left + every / 2; x < bounds.right; x += every) {
      i++;
      final h = _unit(i * 12.9898);
      final rx = x + (h - 0.5) * every * 0.8;
      // Water gathers where it will: a rivulet starts anywhere down the
      // wall and runs some way, not from roof to ground like a seam.
      final top = bounds.top + bounds.height * 0.7 * _unit(i * 3.7);
      final bottom = math.min(
        bounds.bottom,
        top + bounds.height * (0.15 + 0.45 * _unit(i * 7.3)),
      );
      final light = lightAt(Vector2(rx, (top + bottom) / 2)).light;
      final lit = (light - (1 - darkness)).clamp(0.0, 1.0);
      if (lit <= 0.02) {
        continue;
      }
      final a = gloss * lit * (0.25 + 0.35 * h);
      _rivulet.color = const Color(0xFFFFE8C8).withValues(alpha: a * 0.3);
      canvas.drawLine(Offset(rx, top), Offset(rx, bottom), _rivulet);
      // A bead of water sliding down it, catching more of the light.
      final t = (_time * (0.15 + 0.2 * h) + h) % 1.0;
      final y = top + (bottom - top) * t;
      _bead.color = const Color(0xFFFFF0D8).withValues(alpha: a);
      canvas.drawLine(Offset(rx, y - 4), Offset(rx, y), _bead);
    }
    canvas.restore();
  }

  static double _unit(double x) {
    final s = math.sin(x) * 43758.5453;
    return s - s.floorToDouble();
  }

  final Paint _rivulet = Paint()
    ..strokeWidth = 0.6
    ..blendMode = BlendMode.plus;
  final Paint _bead = Paint()
    ..strokeWidth = 1.3
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  /// Draws every [Emissive] part under [parent], each in its own
  /// coordinates: the tree walked with every placed component's transform.
  void _renderGlow(Component parent, Canvas canvas) {
    for (final child in parent.children) {
      if (child is Lighting) {
        continue;
      }
      final placed = child is PositionComponent;
      if (placed) {
        canvas
          ..save()
          ..transform2D(child.transform);
      }
      if (child is Emissive) {
        child.renderEmissive(canvas);
      }
      if (child.children.isNotEmpty) {
        _renderGlow(child, canvas);
      }
      if (placed) {
        canvas.restore();
      }
    }
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
}
