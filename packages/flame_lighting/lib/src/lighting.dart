import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_lighting/src/light_mirror.dart';
import 'package:flame_lighting/src/light_source.dart';
import 'package:flame_lighting/src/lighting_shader.dart';
import 'package:flame_lighting/src/roles.dart';
import 'package:flame_lighting/src/world_lookup.dart';

/// The night over a world, and its lights.
///
/// Drawn over everything below its priority, in three passes:
/// - the night: the view covered with [ambient] at [darkness], every
///   [LightSource] cutting its shape out of that dark with a soft falloff;
/// - the light cast: each light's colour added on top at [glow], so a lamp
///   both reveals the street under it and warms it;
/// - the glow in the mirrors: every [Emissive] part of the world (bulbs, lit
///   windows, the halo [haze] makes round them) and the light hanging in
///   the wet air (a torch's beam, a lamp's cone) given to every
///   [LightMirror] (water, a wet road) to show mirrored as it shows anything
///   - ripples bend it, a rough wet road smears it long.
///
/// The glowing parts themselves are drawn by their components in place, so
/// whatever stands in front of a lamp hides it; the night is cut round
/// every light and its halo so they are not dimmed.
///
/// A [Glossy] surface (a wet wall) draws its own sheen as it draws itself,
/// through [drawSheen], so it stays in its place among the components.
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
    this.floor,
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

  /// The ground band lights lay pools on; `null` takes the world's
  /// [Ground]. Where a light's cone reaches the ground it lays a pool of
  /// light on it - a lamp a wide one under itself, a torch a long one ahead
  /// of the walker.
  Rect? floor;

  /// The lighting drawing now, for the [Emissive] parts it draws.
  static Lighting? get current => _current;
  static Lighting? _current;

  /// How much brighter than drawn the glow being drawn now comes out: above
  /// 1 while a mirror that brings back more than white takes it. What the
  /// air scatters is drawn this much fainter.
  static double get headroom => _headroom;
  static double _headroom = 1;

  final Paint _layer = Paint();
  final Paint _dark = Paint();
  final Paint _cut = Paint()..blendMode = BlendMode.dstOut;
  final Paint _add = Paint()..blendMode = BlendMode.plus;
  final Paint _coneLayer = Paint();
  final Paint _fill = Paint();
  final Paint _coneMask = Paint()..blendMode = BlendMode.dstIn;

  // The world's lights and mirrors, gathered once a frame: every drop and
  // every glint asks for them.
  List<LightSource> get _lights =>
      _lightList ??= _world().descendants().whereType<LightSource>().toList();
  List<LightSource>? _lightList;

  List<LightMirror> get _mirrors =>
      _mirrorList ??= _world().descendants().whereType<LightMirror>().toList();
  List<LightMirror>? _mirrorList;

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

  /// How much light a drop of water at [point] (world coordinates) sends to
  /// the eye, [inFront] world units nearer the eye than the line the lights
  /// stand on (below 0 behind it): the ambient share left of the night plus
  /// every light reaching it, each weighted by how a drop scatters it.
  ///
  /// A drop throws most of the light it gets onward, the way it was going
  /// (Henyey-Greenstein, g [forwardScatter]): a drop between the eye and a
  /// lamp flares, one beside it (seen side-on, 1 by this measure) shows
  /// what reaches it, one behind the lamp less. Not clamped: a drop just in
  /// front of a lamp is many times brighter than one beside it.
  double scatteredLightAt(
    Vector2 point,
    double inFront, {
    double forwardScatter = 0.7,
  }) {
    final g = forwardScatter;
    var total = 1 - darkness;
    for (final light in _lights) {
      final amount = light.lightAt(point, inFront: inFront);
      if (amount <= 0) {
        continue;
      }
      // The light comes from the lamp to the drop; the eye looks back along
      // the depth. The cosine between the two ways.
      final across = point.distanceTo(light.absolutePosition);
      final way = math.sqrt(across * across + inFront * inFront);
      final mu = way < 1e-6 ? 1.0 : inFront / way;
      final phase = math
          .pow((1 + g * g) / (1 + g * g - 2 * g * mu), 1.5)
          .toDouble();
      total += amount * phase;
    }
    return total;
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
      // The air glowing round a source lets its halo through the night.
      _cutHalo(canvas, light);
      _drawPool(canvas, light, _cut, 1);
    }
    canvas.restore();

    if (glow > 0) {
      for (final light in lights) {
        _drawLight(canvas, light, _add, glow, light.strength);
        _drawPool(canvas, light, _add, glow);
      }
    }

    _current = this;
    try {
      for (final mirror in _mirrors) {
        mirror.renderMirroredGlow(
          canvas,
          (c, headroom) {
            _headroom = headroom < 1 ? 1 : headroom;
            try {
              _renderMirrorGlow(world, c, lights);
            } finally {
              _headroom = 1;
            }
          },
        );
      }
    } finally {
      _current = null;
    }
  }

  /// The lighting of the world [component] is in, if it has one.
  static Lighting? of(Component component) => _lookup.of(component);
  static final WorldLookup<Lighting> _lookup = WorldLookup();

  /// Cuts [light]'s halo out of the night, as its haze makes it.
  void _cutHalo(Canvas canvas, LightSource light) {
    final a = (haze * light.strength * 0.6).clamp(0.0, 1.0);
    if (a <= 0 || light.sourceRadius <= 0) {
      return;
    }
    final center = light.absolutePosition.toOffset();
    final radius = light.haloRadius(haze);
    _cut.shader = Gradient.radial(
      center,
      radius,
      [
        const Color(0xFFFFFFFF).withValues(alpha: a),
        const Color(0xFFFFFFFF).withValues(alpha: a * 0.35),
        const Color(0x00FFFFFF),
      ],
      const [0, 0.25, 1],
    );
    canvas.drawCircle(center, radius, _cut);
  }

  /// The pool of light [light] lays on the [floor]: where its cone meets
  /// the ground. From the light's height and the angles of its cone's edges
  /// it works out the stretch of ground lit - ahead of a torch tilted down,
  /// round the foot of a lamp shining straight down - and lays an oval of
  /// light over it on the floor band, fading with the way the light went.
  void _drawPool(Canvas canvas, LightSource light, Paint paint, double amount) {
    final ground = Ground.of(this);
    final floor = this.floor ?? ground?.groundBand();
    final cone = light.coneAngle;
    if (floor == null || cone == null) {
      return;
    }
    final at = light.absolutePosition;
    final height = floor.top - at.y;
    final program = LightingShader.program;
    if (program != null && height > 0) {
      _poolThroughShader(
        canvas,
        program,
        light,
        paint,
        amount,
        floor,
        ground?.depthSpan ?? floor.height * 4,
      );
      return;
    }
    final axis = light.coneDirection;
    if (height <= 0 || math.sin(axis) <= 0.05) {
      return;
    }
    // How far along the beam the ground is, at its axis.
    final along = height / math.sin(axis);
    if (along >= light.radius) {
      return;
    }
    // Where each edge of the cone meets the ground - or, if it points up or
    // runs out first, how far the light reaches along it.
    double meet(double angle) {
      final down = math.sin(angle);
      final reach = light.radius * math.cos(angle);
      if (down <= 0.02) {
        return at.x + reach;
      }
      final x = at.x + height * math.cos(angle) / down;
      return (reach >= 0
          ? math.min(x, at.x + reach)
          : math.max(x, at.x + reach));
    }

    final a = meet(axis - cone / 2);
    final b = meet(axis + cone / 2);
    final left = math.min(a, b);
    final right = math.max(a, b);
    final width = right - left;
    if (width < 1) {
      return;
    }
    final falloff = math.pow(1 - along / light.radius, 2).toDouble();
    final alpha = (amount * light.strength * falloff * 1.6).clamp(0.0, 1.0);
    if (alpha <= 0.01) {
      return;
    }
    final center = Offset(
      (left + right) / 2,
      floor.top + floor.height * 0.35,
    );
    final halfHeight = floor.height * 0.4;
    canvas
      ..save()
      ..clipRect(floor)
      ..translate(center.dx, center.dy)
      ..scale(width / 2, halfHeight);
    paint.shader = Gradient.radial(
      Offset.zero,
      1,
      [
        light.color.withValues(alpha: alpha),
        light.color.withValues(alpha: alpha * 0.4),
        light.color.withValues(alpha: 0),
      ],
      const [0, 0.45, 1],
    );
    canvas
      ..drawCircle(Offset.zero, 1, paint)
      ..restore();
  }

  /// The pool as it falls: every point of [floor] lit by as much of
  /// [light] as reaches it and at the angle it comes in, [span] world units
  /// from the street line to the band's bottom.
  void _poolThroughShader(
    Canvas canvas,
    FragmentProgram program,
    LightSource light,
    Paint paint,
    double amount,
    Rect floor,
    double span,
  ) {
    final at = light.absolutePosition;
    final cone = light.coneAngle!;
    // A shader keeps its uniforms by reference: one per light and pass.
    final shaders = paint == _cut ? _cutPools : _addPools;
    final shader = shaders[light] ??= program.fragmentShader();
    final strength = (amount * light.strength).clamp(0.0, 1.0);
    shader.setFloatUniforms((u) {
      u
        ..setFloat(at.x)
        ..setFloat(at.y)
        ..setFloat(floor.top - at.y)
        ..setFloat(math.cos(light.coneDirection))
        ..setFloat(math.sin(light.coneDirection))
        ..setFloat(cone / 2)
        ..setFloat(cone / 2 * LightSource.softEdge)
        ..setFloat(light.radius)
        ..setFloat(floor.top)
        ..setFloat(floor.height)
        ..setFloat(span)
        ..setFloat(light.color.r)
        ..setFloat(light.color.g)
        ..setFloat(light.color.b)
        ..setFloat(strength);
    });
    canvas.drawRect(floor, paint..shader = shader);
    paint.shader = null;
  }

  final Expando<FragmentShader> _cutPools = Expando();
  final Expando<FragmentShader> _addPools = Expando();

  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _lightList = null;
    _mirrorList = null;
  }

  /// The lights glinting off [wet]: each light's cast once more, over its
  /// wet area only, as strong as it is glossy - and damp trails where water
  /// runs down it: soft, blurred, only just lighter than the wall, and only
  /// where light falls.
  ///
  /// [canvas] is in world coordinates. A [Glossy] component has this drawn
  /// right after itself, so the sheen lies where the wall is: behind
  /// whatever stands in front of it, under the night, and in the water's
  /// mirror too.
  void drawSheen(Canvas canvas, Glossy wet) {
    final lights = _lights.toList();
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
      // A damp trail, not a line: wide, blurred, fading in and out along
      // its length, only just lighter than the wall round it. It breathes
      // slowly as the water on it thickens and thins.
      final breath = 0.75 + 0.25 * math.sin(_time * (0.4 + 0.5 * h) + h * 6);
      final a = gloss * lit * (0.08 + 0.1 * h) * breath;
      // Soft all round by its own gradient - an ellipse fading from its
      // middle out - rather than by a blur: a blur per trail is a pass of
      // its own on the GPU, dozens of them in every reflection of the wall.
      final halfWidth = 4 + 2.5 * _unit(i * 5.1);
      final middle = Offset(rx, top + (bottom - top) * 0.4);
      canvas
        ..save()
        ..translate(middle.dx, middle.dy)
        ..scale(halfWidth, (bottom - top) / 2)
        ..drawRect(
          const Rect.fromLTRB(-1, -1, 1, 1),
          _rivulet..color = Color.fromRGBO(255, 255, 255, a),
        )
        ..restore();
    }
    canvas.restore();
  }

  static double _unit(double x) {
    final s = math.sin(x) * 43758.5453;
    return s - s.floorToDouble();
  }

  final Paint _rivulet = Paint()
    ..blendMode = BlendMode.plus
    ..shader = Gradient.radial(
      Offset.zero,
      1,
      // Warm lamp-lit water; the paint's alpha sets how bright.
      const [Color(0xFFFFE8C8), Color(0x99FFE8C8), Color(0x00FFE8C8)],
      const [0, 0.45, 1],
    );

  /// What water mirrors of the lights: every glowing part, and the light in
  /// the air itself - a torch's beam, a lamp's cone, seen because wet air
  /// scatters them, so as strong as the [haze] is.
  void _renderMirrorGlow(
    Component world,
    Canvas canvas,
    List<LightSource> lights,
  ) {
    final air = glow * (0.2 + 0.5 * haze) / _headroom;
    if (air > 0) {
      for (final light in lights) {
        _drawLight(canvas, light, _mirrorAir, air, light.strength);
      }
    }
    _renderGlow(world, canvas);
  }

  final Paint _mirrorAir = Paint()..blendMode = BlendMode.plus;

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
