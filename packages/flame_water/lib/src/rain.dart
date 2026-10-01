import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/src/rain_catcher.dart';
import 'package:flame_water/src/rain_deflector.dart';
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
    this.windAt,
    this.cloudTop,
    this.releaseShare,
    this.density = 15,
    this.metre = 50,
    this.drying = 1,
    this.color = const Color(0xFFD6E0EE),
    int seed = 7,
    super.priority = 1100,
  }) : wind = wind ?? Vector2(1.6, 0),
       _random = math.Random(seed);

  /// How hard it rains: 1 a steady rain, 2 a downpour, 0.3 a drizzle, 0 dry.
  double intensity;

  /// The wind, metres per second (y down), the same everywhere - unless
  /// [windAt] says how it blows where each drop is.
  Vector2 wind;

  /// The wind at a world point, metres per second, written into `out`
  /// (asked for every drop every step, so it fills a vector rather than
  /// making one); `null`: [wind] everywhere.
  void Function(Vector2 at, Vector2 out)? windAt;

  /// World y where drops leave the cloud; `null`: just above the view.
  double Function()? cloudTop;

  /// Share of the drops that fall from the cloud at world x, `0..1`: where
  /// the cloud is, how thick the rain under it is; `null`: everywhere alike.
  double Function(double x)? releaseShare;

  /// Drops per metre of the view's width per second, at intensity 1.
  double density;

  /// The rain's colour: the light on each drop tints it.
  Color color;

  /// How many drops bounced off a [RainDeflector] since the last call, and
  /// how fast they hit it on average, metres per second: what a game sounds
  /// rain on an umbrella by.
  ({int count, double speed}) takeBounces() {
    final result = (
      count: _bounces,
      speed: _bounces == 0 ? 0.0 : _bounceSpeed / _bounces / metre,
    );
    _bounces = 0;
    _bounceSpeed = 0;
    return result;
  }

  int _bounces = 0;
  double _bounceSpeed = 0;

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

  /// Depths behind the street line where the rain is a veil rather than
  /// drops: so much of it so far off that each drop is a fine faint streak
  /// and the air turns pale. Drawn from a formula, not simulated - each streak
  /// falls on its own phase and wraps round the view - as big, as fast and as
  /// far across as its depth on the world's `Ground` makes it, slanted by the
  /// wind, with the haze that much rain lays over what is behind it; at the
  /// nearest veil, in heavy rain, the spray the drops kick up along the
  /// ground. Each is drawn by the [RainSlice] whose depths hold it.
  List<double> veils = const [];

  /// Streaks of a veil per metre of the view at a depth as big as the street
  /// line, at intensity 1; a farther veil holds more of them (they cover more
  /// air) and shows each smaller.
  double veilDensity = 17.5;

  /// The nearest depth rain falls at: 1 down to the nearest ground in view.
  /// With [behind] 0 and this 0 all of it falls on the street line - flat
  /// rain, for a scene looking at one thing up close.
  double nearest = 1;

  /// The rain over the world [component] is in, if there is one.
  static Rain? of(Component component) => _lookup.of(component);
  static final WorldLookup<Rain> _lookup = WorldLookup();

  /// Drops in the air now, and droplets of bursts.
  @visibleForTesting
  int get dropsInAir => _drops.length;
  @visibleForTesting
  int get droplets => _droplets.length;
  @visibleForTesting
  Iterable<double> get dropXs => _drops.map((d) => d.at.x);
  @visibleForTesting
  Iterable<double> get dropYs => _drops.map((d) => d.at.y);
  @visibleForTesting
  Iterable<Vector2> get dropVelocities => _drops.map((d) => d.velocity);

  /// Drops landed so far, by what caught them (`null`: the bare ground).
  @visibleForTesting
  final Map<Type?, int> landed = {};

  final math.Random _random;
  final List<_Drop> _drops = [];
  final List<_Droplet> _droplets = [];
  double _due = 0;
  bool _started = false;

  Color get _water => color;

  /// The view drops fall over, and where a drop at a depth lands.
  ({
    Rect view,
    double Function(double depth) land,
    double Function(double depth) scale,
  })?
  _frame() {
    final game = findGame();
    final view =
        CameraComponent.currentCamera?.visibleWorldRect ??
        (game is FlameGame ? game.camera.visibleWorldRect : null) ??
        _lastView;
    if (view == null) {
      return null;
    }
    _lastView = view;
    final ground = Ground.of(this);
    return (
      view: view,
      // Where a drop at its depth meets the ground, and how much faster than
      // on the street line it crosses the view: the world's projection. Behind
      // the street line it ends at the line, behind whatever stands there.
      land: ground == null ? (_) => view.bottom : ground.yAt,
      scale: ground == null ? _plainScale : ground.scaleAt,
    );
  }

  /// With no ground: speed on the screen as one over the distance, the
  /// nearest drops two and a half times as fast as on the street line.
  static double _plainScale(double depth) => 1 / (1 - 0.6 * depth);

  Rect? _lastView;

  final Vector2 _air = Vector2.zero();

  /// The wind's x at [at], metres per second.
  double _windX(Vector2 at) {
    final field = windAt;
    if (field == null) {
      return wind.x;
    }
    field(at, _air);
    return _air.x;
  }

  /// How far past the view drops are born and kept, world units: a metre,
  /// so the wind carries them into the view rather than they pop in.
  double get _margin => metre;

  _Drop _newDrop(
    Rect view,
    double Function(double) land,
    double Function(double) scale,
    double lead,
  ) {
    // A share of the rain falls behind the street line (negative depth):
    // onto roofs and behind the houses, never onto the road.
    final depth = behind + (nearest - behind) * _random.nextDouble();
    final diameter = RainDrops.diameterMm(_random.nextDouble(), intensity);
    final terminal = RainDrops.terminalSpeed(diameter);
    // Seen nearer, a drop crosses the view faster: its speed on the screen
    // goes as one over its distance - half as far, twice as fast.
    final perspective = scale(depth);
    final fall = terminal * metre * perspective;
    // It lands somewhere over the view; it left the cloud upwind of there by
    // as far as the wind carries it on the way down.
    final top = cloudTop?.call() ?? view.top - _margin;
    final landing = land(depth);
    final target =
        view.left - _margin + _random.nextDouble() * (view.width + 2 * _margin);
    final windX = _windX(Vector2(target, (top + landing) / 2)) * metre;
    final fallTime = math.max(landing - top, 0) / fall;
    final born = target - windX * perspective * fallTime;
    return _Drop(
      at: Vector2(
        born,
        // Spread over the way it falls in this step: drops born in one step
        // at one height would fall as a line.
        top - _random.nextDouble() * fall * lead,
      ),
      velocity: Vector2(windX * perspective, fall),
      land: landing,
      depth: depth,
      perspective: perspective,
      response: RainDrops.responseSec(terminal),
      fall: fall,
      diameter: diameter,
      strength: ((diameter - RainDrops.minMm) / 2.5).clamp(0.25, 1.0),
    );
  }

  // A veil's streaks: where across the view, how far down their fall, how
  // fast against the others - fixed once, for every veil.
  static const int _veilMax = 1600;
  late final Float64List _veilX = _spread();
  late final Float64List _veilPhase = _spread();
  late final Float64List _veilSpeed = Float64List.fromList([
    for (var i = 0; i < _veilMax; i++) 0.8 + 0.4 * _random.nextDouble(),
  ]);
  Float64List _spread() => Float64List.fromList([
    for (var i = 0; i < _veilMax; i++) _random.nextDouble(),
  ]);
  double _veilTime = 0;
  double _veilSlope = 0;
  Float32List _veilLines = Float32List(0);
  final Paint _veilStreak = Paint();
  final Paint _veilHaze = Paint();
  final Paint _veilSpray = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    _veilTime += dt;
    // The veil's slant eases after the wind, so a gust sweeps through it
    // rather than snapping it.
    final seen = _lastView;
    if (seen != null) {
      final fall = RainDrops.terminalSpeed(2);
      final windX = _windX(Vector2(seen.center.dx, seen.center.dy));
      final target = (windX / fall).clamp(-3.0, 3.0);
      _veilSlope += (target - _veilSlope) * (1 - math.exp(-dt / 0.4));
    }
    final frame = _frame();
    if (frame == null) {
      return;
    }
    final (:view, :land, :scale) = frame;
    if (!_started) {
      _started = true;
      // The rain is already falling when the scene opens: as many drops as
      // fall over a whole way down from the cloud, spread along it.
      final top = cloudTop?.call() ?? view.top - _margin;
      final way =
          math.max(land(0) - top, 0) / (RainDrops.terminalSpeed(2) * metre);
      final inAir = (density * view.width / metre * intensity * way).round();
      for (var i = 0; i < inAir; i++) {
        final drop = _newDrop(view, land, scale, 0);
        // Somewhere along its way down already.
        final share = _random.nextDouble();
        final fallTime = (drop.land - drop.at.y) / drop.fall;
        drop.at
          ..x += drop.velocity.x * fallTime * share
          ..y += (drop.land - drop.at.y) * share;
        if (_released(drop)) {
          _drops.add(drop);
        }
      }
    }
    _due += dt * density * view.width / metre * intensity;
    while (_due >= 1) {
      _due -= 1;
      final drop = _newDrop(view, land, scale, dt);
      if (_released(drop)) {
        _drops.add(drop);
      }
    }
    final world = _world();
    final catchers = world.descendants().whereType<RainCatcher>().toList();
    final deflectors = world.descendants().whereType<RainDeflector>().toList();
    for (final d in _drops) {
      final from = d.at.y;
      _from.setFrom(d.at);
      // It takes up the wind where it is as fast as its size lets it.
      final field = windAt;
      if (field == null) {
        _air.setFrom(wind);
      } else {
        field(d.at, _air);
      }
      final k = RainDrops.follow(dt, d.response);
      d.velocity
        ..x += (_air.x * metre * d.perspective - d.velocity.x) * k
        ..y += (d.fall + _air.y * metre - d.velocity.y) * k;
      d.at.addScaled(d.velocity, dt);
      if (_deflect(d, deflectors)) {
        continue;
      }
      d.caught = _catch(d, from, catchers);
    }
    // A drop goes once it has crossed the view with the wind; one still on
    // its way into it - born upwind, far off in a strong wind - stays.
    _drops.removeWhere(
      (d) =>
          d.caught ||
          (d.velocity.x >= 0
              ? d.at.x > view.right + 4 * _margin
              : d.at.x < view.left - 4 * _margin),
    );
    for (final p in _droplets) {
      p.age += dt;
      p.velocity.y += 18 * metre * dt;
      p.at.addScaled(p.velocity, dt);
    }
    _droplets.removeWhere((p) => p.age >= p.life || p.at.y > p.floor);
    _shade();
  }

  final Vector2 _from = Vector2.zero();

  /// Whether the cloud lets [d] fall where it was born.
  bool _released(_Drop d) {
    final share = releaseShare;
    return share == null || _random.nextDouble() < share(d.at.x);
  }

  /// Whether a deflector on its way turned [d] back (moving it and its
  /// velocity as it says).
  bool _deflect(_Drop d, List<RainDeflector> deflectors) {
    for (final deflector in deflectors) {
      final speed = d.velocity.length;
      if (deflector.deflect(_from, d.at, d.velocity, d.depth)) {
        // Heard once, as it falls on it; flying off, it may touch it again.
        if (!d.bounced) {
          d.bounced = true;
          _bounces++;
          _bounceSpeed += speed;
        }
        return true;
      }
    }
    return false;
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
            side * (0.4 + 1.4 * _random.nextDouble()) * metre * size,
            -(1.8 + 2.4 * _random.nextDouble()) * metre * size,
          ),
          floor: at.y + 0.02 * metre,
          life: 0.35,
          width: (0.02 + 0.03 * d.depth) * metre,
          depth: d.depth,
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

  /// The veil at [depth]: haze, streaks, and at the nearest veil the spray.
  void _renderVeil(Canvas canvas, double depth) {
    final view = _lastView;
    final ground = Ground.of(this);
    final rain = intensity.clamp(0.0, 2.5);
    if (view == null || ground == null || rain <= 0.01) {
      return;
    }
    final scale = ground.scaleAt(depth);
    // The rain between the eye and what is behind the veil pales it: the
    // more, the harder it rains and the farther off.
    final haze = (0.15 * rain * (1 - scale)).clamp(0.0, 0.3);
    _veilHaze.color = color.withValues(alpha: color.a * haze);
    canvas.drawRect(view.inflate(metre), _veilHaze);

    final count = math.min(
      _veilMax,
      (veilDensity * view.width / metre / scale * rain).round(),
    );
    if (_veilLines.length < count * 4) {
      _veilLines = Float32List(count * 4);
    }
    final height = view.height;
    final slope = _veilSlope;
    final width = view.width + height * slope.abs();
    // How far the veil has moved against the view, as anything at its depth
    // does (parallax).
    final shift = view.center.dx * (1 - scale);
    final fallSpeed = RainDrops.terminalSpeed(2) * metre * scale;
    final length = 0.34 * scale * metre;
    var n = 0;
    for (var i = 0; i < count; i++) {
      // Each veil its own streaks: offset by the depth.
      final k = (i + (depth * 997).round()) % _veilMax;
      final fallen =
          (_veilPhase[k] + _veilTime * fallSpeed * _veilSpeed[k] / height) %
          1.0;
      final y = view.top + fallen * height;
      final along = _veilX[k] * width - shift + (y - view.top) * slope;
      final x =
          view.left -
          (slope > 0 ? height * slope : 0) +
          (along % width + width) % width;
      _veilLines
        ..[n++] = x
        ..[n++] = y
        ..[n++] = x - slope * length
        ..[n++] = y - length;
    }
    _veilStreak
      ..color = color.withValues(alpha: color.a * 0.4 * math.sqrt(scale))
      ..strokeWidth = 0.018 * scale * metre;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_veilLines, 0, n),
      _veilStreak,
    );

    // Heavy rain bursting on the ground throws up a low mist along it.
    if (depth == veils.reduce(math.max)) {
      final spray = (0.35 * (rain - 0.8)).clamp(0.0, 0.35);
      if (spray > 0) {
        final line = ground.yAt(0);
        final top = line - 0.7 * metre;
        _veilSpray.shader = Gradient.linear(Offset(0, line), Offset(0, top), [
          color.withValues(alpha: color.a * spray),
          color.withValues(alpha: 0),
        ]);
        canvas.drawRect(
          Rect.fromLTRB(view.left - metre, top, view.right + metre, line),
          _veilSpray,
        );
      }
    }
  }

  /// Whether it draws itself; off when [RainSlice]s draw it by depth, each
  /// in its own place among the components.
  bool drawsItself = true;

  @override
  void render(Canvas canvas) {
    if (drawsItself) {
      renderDepths(canvas);
    }
  }

  /// Draws the drops and droplets falling at depths from [from] up to (not
  /// including) [to].
  void renderDepths(
    Canvas canvas, {
    double from = double.negativeInfinity,
    double to = double.infinity,
  }) {
    final mirror = ReflectionPass.current;
    if (mirror == null) {
      // A veil is far behind; water does not need it.
      for (final depth in veils) {
        if (depth >= from && depth < to) {
          _renderVeil(canvas, depth);
        }
      }
    }
    // In water, only what stands across from it.
    final area = ReflectionPass.area;
    final left = area?.left ?? double.negativeInfinity;
    final right = area?.right ?? double.infinity;
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
      if (d.depth < from || d.depth >= to) {
        continue;
      }
      // Its streak trails back along its motion, up to a metre and more.
      if (d.at.x < left - _margin || d.at.x > right + _margin) {
        continue;
      }
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
        (0.016 + 0.028 * d.depth * (0.6 + 0.4 * d.strength)) * metre,
        d.color.toARGB32(),
      );
    }
    for (final p in _droplets) {
      if (p.depth < from || p.depth >= to || p.at.x < left || p.at.x > right) {
        continue;
      }
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

  /// Whether it has bounced off a deflector already.
  bool bounced = false;

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
    required this.depth,
  });

  final Vector2 at;
  final Vector2 velocity;
  final double floor;
  final double life;
  final double width;
  final double depth;
  double age = 0;

  /// How it looks this frame.
  Color color = const Color(0x00000000);
}

/// The rain falling in a range of depths, drawn where this sits among the
/// components: rain behind the street line under what stands on it, the
/// rest over it. Set the rain's `drawsItself` off and give it one slice for
/// each range. Water mirrors a slice as it mirrors the rain.
class RainSlice extends Component with Reflectable {
  RainSlice(
    this.rain, {
    this.from = double.negativeInfinity,
    this.to = double.infinity,
    super.priority,
  });

  final Rain rain;

  /// The depths it draws, from [from] up to (not including) [to].
  final double from;
  final double to;

  @override
  void render(Canvas canvas) => rain.renderDepths(canvas, from: from, to: to);
}
