import 'dart:math' as math;
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
/// what depends on it (water astir, walls getting wet).
class Rain extends Component with Reflectable {
  Rain({
    this.intensity = 1,
    Vector2? wind,
    this.density = 0.3,
    this.metre = 50,
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

  /// How far behind the street line rain falls too, as a depth below 0: the
  /// rain over the roofs and behind the houses, which a [RainCatcher] there
  /// (a roof) catches and the ground never sees.
  double behind = -0.25;

  /// The rain over the world [component] is in, if there is one.
  static Rain? of(Component component) {
    var top = component;
    for (final a in component.ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top.descendants().whereType<Rain>().firstOrNull;
  }

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
  final Paint _streak = Paint()..strokeCap = StrokeCap.round;
  final Paint _splash = Paint()..strokeCap = StrokeCap.round;

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
  }

  /// Whether a catcher (or the ground) stopped [d] on its way from [from]:
  /// the first on the way takes it.
  bool _catch(_Drop d, double from, List<RainCatcher> catchers) {
    RainCatcher? by;
    var at = double.infinity;
    for (final c in catchers) {
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

  /// A drop bursting where it lands: a few droplets thrown up and out,
  /// higher for a near, heavy drop.
  void _burst(Vector2 at, _Drop d) {
    final size = (0.5 + 0.5 * d.depth) * d.strength;
    final count = 2 + (size * 3).round();
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

  /// The rain's colour at [at], [alpha] times as bright as the light there.
  Color _lit(Lighting? lighting, Vector2 at, double alpha) {
    if (lighting == null || ReflectionPass.isActive) {
      return _water.withValues(alpha: alpha);
    }
    final (:light, :color) = lighting.lightAt(at);
    return Color.lerp(
      _water,
      color,
      (light - (1 - lighting.darkness)) * 0.8,
    )!.withValues(alpha: (alpha * light * 1.3).clamp(0.0, 1.0));
  }

  @override
  void render(Canvas canvas) {
    final lighting = Lighting.of(this);
    for (final d in _drops) {
      final speed = d.velocity.length;
      final length = RainDrops.streakLength(speed / metre) * metre;
      _streak
        ..color = _lit(
          lighting,
          d.at,
          (0.3 + 0.6 * d.depth) * (0.6 + 0.4 * d.strength),
        )
        ..strokeWidth = 0.8 + 1.4 * d.depth * (0.6 + 0.4 * d.strength);
      final head = Offset(d.at.x, math.min(d.at.y, d.land));
      final back = speed < 1e-6
          ? Offset.zero
          : Offset(d.velocity.x, d.velocity.y) / speed * length;
      canvas.drawLine(head - back, head, _streak);
    }
    for (final p in _droplets) {
      _splash
        ..strokeWidth = p.width
        ..color = _lit(lighting, p.at, 0.9);
      canvas.drawPoints(PointMode.points, [p.at.toOffset()], _splash);
    }
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

  /// 0..1: a heavy drop against a fine one.
  final double strength;

  bool caught = false;
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
}
