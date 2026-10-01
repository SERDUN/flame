import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/src/rain_catcher.dart';
import 'package:flame_water/src/rain_drops.dart';
import 'package:flame_water/src/reflection_pass.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Rain over a side-view world.
///
/// Drops fall over the camera's view as real rain does ([RainDrops]): their
/// sizes drawn for how hard it rains ([intensity]), each falling at its
/// size's speed and taking up the [wind] as fast as its size lets it, drawn
/// as the streak a camera would catch. [metre] is how many world units make
/// a metre.
///
/// Seen from the side, each drop falls at its own depth: it would land on
/// the world's [Ground] that far towards the viewer - a far one on the line
/// things stand on, a near one low in the view - and a near drop looks
/// longer, brighter and faster. On its way it may be caught by a
/// [RainCatcher] (a roof, a puddle, the road): the first one it reaches
/// takes it, and it bursts into droplets there if the catcher splashes.
///
/// Under a `Lighting` a drop is as bright as the light where it is and takes
/// its colour, so rain shines in a lamp's cone; keep the rain's priority
/// above the lighting's for that. [Rain.of] finds the rain over a world, for
/// what depends on it (water astir, things getting wet and drying).
class Rain extends Component with Reflectable {
  Rain({
    this.intensity = 1,
    Vector2? wind,
    this.density = 0.3,
    this.metre = 50,
    this.drying = 1,
    int seed = 7,
    super.priority = 1100,
  }) : wind = wind ?? Vector2(1.6, 0),
       _random = math.Random(seed);

  /// How hard it rains: 1 a steady rain, 2 a downpour, 0.3 a drizzle, 0 dry.
  double intensity;

  /// The wind, metres per second (y down).
  Vector2 wind;

  /// Drops per world unit of the view's width per second, at intensity 1.
  double density;

  /// World units in a metre.
  double metre;

  /// How fast wet things dry in this weather: 1 the usual, 0 not at all
  /// (a still, cold, damp night), 5 in a warm wind. Each `Wettable` dries at
  /// its own rate times this.
  double drying;

  /// How far behind the street line rain falls too, as a depth below 0: the
  /// rain over the roofs and behind the houses, which a [RainCatcher] there
  /// (a roof) catches and the ground never sees.
  double behind = -0.25;

  /// The rain over the world [component] is in, if there is one.
  static Rain? of(Component component) => _lookup.of(component);
  static final WorldLookup<Rain> _lookup = WorldLookup();

  /// Drops in the air now, and droplets of bursts.
  @visibleForTesting
  int get dropsInAir => _drops.length;
  @visibleForTesting
  int get droplets => _droplets.length;

  /// Drops landed so far, by what caught them (`null`: the bare ground).
  @visibleForTesting
  final Map<Type?, int> landed = {};

  final math.Random _random;
  final List<_Drop> _drops = [];
  final List<_Droplet> _droplets = [];
  double _due = 0;
  bool _started = false;

  static const Color _water = Color(0xFFD6E0EE);

  /// The view drops fall over, and where a drop at a depth lands.
  ({Rect view, double Function(double depth) land})? _frame() {
    final game = findGame();
    final view =
        CameraComponent.currentCamera?.visibleWorldRect ??
        (game is FlameGame ? game.camera.visibleWorldRect : null) ??
        _lastView;
    if (view == null) {
      return null;
    }
    _lastView = view;
    final ground = Ground.of(this)?.groundBand();
    return (
      view: view,
      land: ground == null
          ? (_) => view.bottom
          // Behind the street line a drop never reaches the ground in view:
          // it ends at the line, behind whatever stands there.
          : (depth) => depth < 0
                ? ground.top
                : ground.top + 4 + depth * (ground.height - 8),
    );
  }

  Rect? _lastView;

  _Drop _newDrop(Rect view, double Function(double) land, double lead) {
    // A share of the rain falls behind the street line (negative depth):
    // onto roofs and behind the houses, never onto the road.
    final depth = behind + (1 - behind) * _random.nextDouble();
    final diameter = RainDrops.diameterMm(_random.nextDouble(), intensity);
    final terminal = RainDrops.terminalSpeed(diameter);
    // A near drop crosses the view faster, as anything near does.
    // Seen nearer, a drop crosses the view faster: its speed on the screen
    // goes as one over its distance - half as far, twice as fast.
    final perspective = 1 / (1 - 0.6 * depth);
    final fall = terminal * metre * perspective;
    return _Drop(
      at: Vector2(
        view.left - 40 + _random.nextDouble() * (view.width + 80),
        // Spread over the way it falls in this step: drops born in one step
        // at one height would fall as a line.
        view.top - 30 - _random.nextDouble() * fall * lead,
      ),
      velocity: Vector2(wind.x * metre * perspective, fall),
      land: land(depth),
      depth: depth,
      perspective: perspective,
      response: RainDrops.responseSec(terminal),
      fall: fall,
      diameter: diameter,
      strength: ((diameter - RainDrops.minMm) / 2.5).clamp(0.25, 1.0),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final frame = _frame();
    if (frame == null) {
      return;
    }
    final (:view, :land) = frame;
    if (!_started) {
      _started = true;
      // The rain is already falling when the scene opens.
      final inAir = (density * view.width * intensity * 0.6).round();
      for (var i = 0; i < inAir; i++) {
        final drop = _newDrop(view, land, 0);
        drop.at.y = view.top + _random.nextDouble() * (drop.land - view.top);
        _drops.add(drop);
      }
    }
    _due += dt * density * view.width * intensity;
    while (_due >= 1) {
      _due -= 1;
      _drops.add(_newDrop(view, land, dt));
    }
    final catchers = _world().descendants().whereType<RainCatcher>().toList();
    for (final d in _drops) {
      final from = d.at.y;
      // It takes up the wind as fast as its size lets it.
      final k = RainDrops.follow(dt, d.response);
      d.velocity
        ..x += (wind.x * metre * d.perspective - d.velocity.x) * k
        ..y += (d.fall + wind.y * metre - d.velocity.y) * k;
      d.at.addScaled(d.velocity, dt);
      d.caught = _catch(d, from, catchers);
    }
    _drops.removeWhere(
      (d) => d.caught || d.at.x < view.left - 200 || d.at.x > view.right + 200,
    );
    for (final p in _droplets) {
      p.age += dt;
      p.velocity.y += 900 * dt;
      p.at.addScaled(p.velocity, dt);
    }
    _droplets.removeWhere((p) => p.age >= p.life || p.at.y > p.floor);
    _shade();
  }

  /// Whether a catcher (or the ground) stopped [d] on its way from [from]:
  /// the first on the way takes it.
  bool _catch(_Drop d, double from, List<RainCatcher> catchers) {
    RainCatcher? by;
    var at = double.infinity;
    for (final c in catchers) {
      final front = c.frontDepth;
      if (front != null && d.depth >= front) {
        // It falls in front of this one.
        continue;
      }
      final y = c.catchDrop(d.at.x, from, d.at.y, d.depth);
      if (y == null) {
        continue;
      }
      if (y < at || (y == at && by != null && c.catchOrder > by.catchOrder)) {
        at = y;
        by = c;
      }
    }
    if (by == null) {
      if (d.at.y < d.land) {
        return false;
      }
      landed.update(null, (n) => n + 1, ifAbsent: () => 1);
      // The bare ground; behind the street line, nothing to see.
      if (d.depth >= 0) {
        _burst(Vector2(d.at.x, d.land), d);
      }
      return true;
    }
    landed.update(by.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    final point = Vector2(d.at.x, at);
    if (by.splashes) {
      _burst(point, d);
    }
    by.onDrop(point, d.strength);
    return true;
  }

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

  /// How hard a drop of [diameterMm] hits at [speed] m/s, as the number
  /// that tells whether it splashes: K = We^0.5 * Re^0.25, from its inertia
  /// against the water's surface tension and viscosity.
  static double impactNumber(double diameterMm, double speed) {
    final d = diameterMm / 1000;
    final weber = 1000 * speed * speed * d / 0.072;
    final reynolds = 1000 * speed * d / 0.001;
    return math.sqrt(weber) * math.pow(reynolds, 0.25);
  }

  /// Above this [impactNumber] a drop splashes on a rough solid surface; below
  /// it the drop only spreads and wets.
  static const double splashThreshold = 57.7;

  /// A drop bursting where it lands, if it hits hard enough to splash: a
  /// few droplets thrown up and out, more the harder it hits, higher for a
  /// near, heavy drop. A fine drop only wets.
  void _burst(Vector2 at, _Drop d) {
    final speed = d.velocity.length / (metre * d.perspective);
    final k = impactNumber(d.diameter, speed);
    if (k <= splashThreshold) {
      return;
    }
    final size = (0.5 + 0.5 * d.depth) * d.strength;
    final count = (1 + 2 * (k / splashThreshold - 1) + size * 2).round().clamp(
      1,
      7,
    );
    for (var i = 0; i < count; i++) {
      final side = _random.nextBool() ? 1 : -1;
      _droplets.add(
        _Droplet(
          at: at.clone(),
          velocity: Vector2(
            side * (20 + 70 * _random.nextDouble()) * size,
            -(90 + 120 * _random.nextDouble()) * size,
          ),
          floor: at.y + 1,
          life: 0.35,
          width: 1 + 1.5 * d.depth,
        ),
      );
    }
  }

  /// How bright a drop seen side-on in full light shows: the one scale the
  /// streaks are drawn at; everything else about how bright a drop is
  /// follows from the light on it and how it moves.
  static const double visibility = 0.7;

  /// A 2 mm drop's diameter over its terminal speed: what a streak's
  /// exposure is measured against.
  static final double _referenceExposure = 2 / RainDrops.terminalSpeed(2);

  /// Works out how every drop and droplet looks this frame, once: the rain
  /// is drawn again in every water's reflection.
  void _shade() {
    final lighting = Lighting.of(this);
    final span = Ground.of(this)?.depthSpan ?? 0;
    for (final d in _drops) {
      final speed = d.velocity.length;
      // A drop is seen by the light it throws to the eye - from the lamps
      // round it, far more from one it is in front of - and a streak is
      // that light spread over the way it falls in an exposure: each point
      // of it lit for its diameter over its speed. A fine slow drop and a
      // heavy fast one come out alike; a fast small one is a faint line.
      final trueSpeed = math.max(speed / (metre * d.perspective), 0.5);
      final exposure = d.diameter / trueSpeed / _referenceExposure;
      if (lighting == null) {
        d.color = _water.withValues(alpha: (visibility * exposure).clamp(0, 1));
        continue;
      }
      final lit = lighting.dropLightAt(d.at, d.depth * span);
      d.color = Color.lerp(
        _water,
        lit.color,
        (lit.light - (1 - lighting.darkness)) * 0.8,
      )!.withValues(alpha: (visibility * lit.scattered * exposure).clamp(0, 1));
    }
    for (final p in _droplets) {
      if (lighting == null) {
        p.color = _water.withValues(alpha: 0.9);
        continue;
      }
      final (:light, :color) = lighting.lightAt(p.at);
      p.color = Color.lerp(
        _water,
        color,
        (light - (1 - lighting.darkness)) * 0.8,
      )!.withValues(alpha: (0.9 * light).clamp(0, 1));
    }
  }

  // The streaks and droplets as triangles: one draw for the whole rain.
  Float32List _positions = Float32List(0);
  Int32List _colors = Int32List(0);
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final mirror = ReflectionPass.current;
    final quads = _drops.length + _droplets.length;
    if (quads == 0) {
      return;
    }
    // Each streak is a strip three vertices wide: full down its middle,
    // clear at its edges - soft-edged as a line drawn smooth, which bare
    // triangles are not. Four triangles, twelve vertices.
    if (_positions.length < quads * 24) {
      _positions = Float32List(quads * 24 * 2);
      _colors = Int32List(quads * 12 * 2);
    }
    var v = 0;
    var c = 0;
    void point(double x, double y, int argb) {
      _positions[v++] = x;
      _positions[v++] = y;
      _colors[c++] = argb;
    }

    void quad(double hx, double hy, double tx, double ty, double w, int argb) {
      var nx = ty - hy;
      var ny = hx - tx;
      final len = math.sqrt(nx * nx + ny * ny);
      if (len < 1e-6) {
        nx = w;
        ny = 0;
      } else {
        nx *= w / len;
        ny *= w / len;
      }
      final clear = argb & 0x00FFFFFF;
      // tail edge, tail middle, head middle; tail edge, head middle, head
      // edge - on each side.
      for (final s in const [-1.0, 1.0]) {
        point(tx + s * nx, ty + s * ny, clear);
        point(tx, ty, argb);
        point(hx, hy, argb);
        point(tx + s * nx, ty + s * ny, clear);
        point(hx, hy, argb);
        point(hx + s * nx, hy + s * ny, clear);
      }
    }

    for (final d in _drops) {
      final speed = d.velocity.length;
      final length = RainDrops.streakLength(speed / metre) * metre;
      // In water a drop is mirrored about the spot it falls to.
      final shift = mirror?.mirrorShift(d.land) ?? 0;
      final hx = d.at.x;
      final hy = math.min(d.at.y, d.land) + shift;
      final bx = speed < 1e-6 ? 0.0 : d.velocity.x / speed * length;
      final by = speed < 1e-6 ? 0.0 : d.velocity.y / speed * length;
      quad(
        hx,
        hy,
        hx - bx,
        hy - by,
        0.8 + 1.4 * d.depth * (0.6 + 0.4 * d.strength),
        d.color.toARGB32(),
      );
    }
    for (final p in _droplets) {
      final shift = mirror?.mirrorShift(p.floor) ?? 0;
      final y = p.at.y + shift;
      quad(
        p.at.x,
        y - p.width / 2,
        p.at.x,
        y + p.width / 2,
        p.width,
        p.color.toARGB32(),
      );
    }
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, v),
      colors: Int32List.sublistView(_colors, 0, c),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
  }
}

class _Drop {
  _Drop({
    required this.at,
    required this.velocity,
    required this.land,
    required this.depth,
    required this.perspective,
    required this.response,
    required this.fall,
    required this.diameter,
    required this.strength,
  });

  final Vector2 at;
  final Vector2 velocity;

  /// World y where it meets the ground, at its depth.
  final double land;

  /// Below 0 behind the street line; 0 on the line things stand on .. 1
  /// near.
  final double depth;

  /// How much faster than a far drop it crosses the view.
  final double perspective;

  /// How quickly it takes up the wind, s.
  final double response;

  /// Its fall speed on the screen, world units a second.
  final double fall;

  /// mm.
  final double diameter;

  /// 0..1: a heavy drop against a fine one.
  final double strength;

  bool caught = false;

  /// How it looks this frame.
  Color color = const Color(0x00000000);
}

class _Droplet {
  _Droplet({
    required this.at,
    required this.velocity,
    required this.floor,
    required this.life,
    required this.width,
  });

  final Vector2 at;
  final Vector2 velocity;
  final double floor;
  final double life;
  final double width;
  double age = 0;

  /// How it looks this frame.
  Color color = const Color(0x00000000);
}
