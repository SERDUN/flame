import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_water/src/rain_catcher.dart';
import 'package:flame_water/src/rain_deflector.dart';
import 'package:flame_water/src/rain_drops.dart';
import 'package:flame_water/src/rain_pool.dart';
import 'package:flame_water/src/rain_streaks.dart';
import 'package:flame_water/src/rain_veil.dart';
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
/// the street's ground that far towards the viewer - a far one on the line
/// things stand on, a near one low in the view - and a near drop looks
/// longer, brighter and faster. On its way it may be caught by a
/// [RainCatcher] (a roof, a puddle, the road): the first one it reaches
/// takes it, and it bursts into droplets there if it hits harder than what
/// the catcher is made of lets it ([Substance.splashAbove]).
///
/// It reads everything from the stage's frame: the view, the street's
/// projection, the light. Under a `Lighting` a drop is as bright as the
/// light where it is and takes its colour, so rain shines in a lamp's cone.
/// Drawn over the lighting, a drop shows as lit as it is; drawn under it
/// ([RainSlice] below the lighting), the light where it is is laid over it,
/// so it carries no more than that light leaves out. [Rain.of] finds the
/// rain over a world, for what depends on it (water astir, things getting
/// wet and drying).
///
/// It is the stage's [Weather] too: it rains [rainMmPerHour] (its
/// [intensity] of a steady 6 mm an hour), in its [wind], in air of its
/// [humidity] and [temperature], under its [cloudCover], the world's time
/// running at its [pace] - what every `Wettable` fills and dries by.
class Rain extends Component with OnStage, Reflectable, Weather {
  Rain({
    this.intensity = 1,
    Vector2? wind,
    this.windAt,
    this.cloudTop,
    this.releaseShare,
    this.density = 15,
    this.metre = 50,
    this.humidity = 0.95,
    this.temperature = 12,
    this.cloudCover = 1,
    this.pace = 1,
    this.color = const Color(0xFFD6E0EE),
    int seed = 7,
    super.priority = 1100,
  }) : wind = wind ?? Vector2(1.6, 0),
       _random = math.Random(seed);

  /// How hard it rains: 1 a steady rain, 2 a downpour, 0.3 a drizzle, 0 dry.
  double intensity;

  /// The wind, metres per second (y down), the same everywhere - unless
  /// [windAt] says how it blows where each drop is.
  @override
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

  /// How many drops bounced off a [RainDeflector] since the last call, how
  /// fast they hit it on average, metres per second, and how loud what they
  /// hit is on average ([Substance.loudness]): what a game sounds rain on
  /// an umbrella by.
  ({int count, double speed, double loudness}) takeBounces() {
    final result = (
      count: _bounces,
      speed: _bounces == 0 ? 0.0 : _bounceSpeed / _bounces / metre,
      loudness: _bounces == 0 ? 0.0 : _bounceLoudness / _bounces,
    );
    _bounces = 0;
    _bounceSpeed = 0;
    _bounceLoudness = 0;
    return result;
  }

  int _bounces = 0;
  double _bounceSpeed = 0;
  double _bounceLoudness = 0;

  /// Where the rain is heard from: world x and y, and z how far in front of
  /// the street line, world units (a walker's head under the umbrella).
  /// `null`: the eye, every drop as near as its perspective says.
  Vector3? listener;

  /// The rain heard over the `seconds` since the last call, by what the
  /// drops struck: the ground ([ground]), a [RainCatcher]'s or a
  /// [RainDeflector]'s surface (a drop is heard once, as it falls on the
  /// umbrella, not again as it flies off). Each strike carries the energy
  /// the ear gets from it: as loud as what it struck ([Substance.loudness]),
  /// as hard as the drop hits (its mass, the cube of its diameter, times its
  /// speed squared, against a 2 mm drop at 8 m/s), and fainter by the square
  /// of its distance from the [listener] (no nearer than 0.2 m). Strikes add
  /// up by their energy: the patter of a surface goes as the square root of
  /// its energy per second. So a game hears the rain its world has: where
  /// more of it falls, on what, and how near.
  ({double seconds, List<RainStrikes> on}) takeImpacts() {
    final result = (
      seconds: _heardSeconds,
      on: [
        for (final s in _strikes.values)
          if (s.count > 0) s.taken(),
      ],
    );
    _heardSeconds = 0;
    return result;
  }

  final Map<Substance, RainStrikes> _strikes = {};
  double _heardSeconds = 0;
  StreetProjection? _heardFrom;

  void _heard(
    int i,
    Substance on,
    double x,
    double y,
    double speed, {
    double? atDepth,
  }) {
    final listener = this.listener;
    double r2;
    if (listener == null) {
      final p = _drops.perspective(i);
      r2 = 1 / (p * p);
    } else {
      final ahead = _heardFrom?.ahead(atDepth ?? _drops.depth(i)) ?? 0;
      final dx = x - listener.x;
      final dy = y - listener.y;
      final dz = ahead - listener.z;
      r2 = (dx * dx + dy * dy + dz * dz) / (metre * metre);
    }
    final d = _drops.diameter(i) / 2;
    final v = speed / metre / 8;
    final energy = on.loudness * d * d * d * v * v / math.max(r2, 0.04);
    (_strikes[on] ??= RainStrikes(on)).add(energy);
  }

  /// World units in a metre.
  double metre;

  // As the weather of its stage: the rain it is, and the air it falls in.

  @override
  double get rainMmPerHour => intensity * WeatherState.tunedRainMmPerHour;

  @override
  double humidity;

  @override
  double temperature;

  @override
  double cloudCover;

  @override
  double pace;

  /// What the ground is, where no catcher takes a drop: whether a drop
  /// splashes on it.
  Substance ground = Substance.asphalt;

  /// How far behind the street line rain falls too, as a depth below 0: the
  /// rain over the roofs and behind the houses, which a [RainCatcher] there
  /// (a roof) catches and the ground never sees.
  double behind = -0.25;

  /// Depths behind the street line where the rain is a veil rather than
  /// drops: so much of it so far off that each drop is a fine faint streak
  /// and the air turns pale. Drawn from a formula, not simulated - each streak
  /// falls on its own phase and wraps round the view - as big, as fast and as
  /// far across as its depth on the street makes it, slanted by the
  /// wind; at the nearest veil, in heavy rain, the spray the drops kick up
  /// along the ground. Each is drawn by the [RainSlice] whose depths hold it.
  /// The haze the rain lays over what is behind is the air's (its share of
  /// the air's extinction, drawn by `AirVeil`).
  List<double> veils = const [];

  /// Streaks of a veil per metre of the view at a depth as big as the street
  /// line, at intensity 1; a farther veil holds more of them (they cover more
  /// air) and shows each smaller.
  double veilDensity = 17.5;

  /// The nearest depth rain falls at: 1 down to the nearest ground in view.
  /// With [behind] 0 and this 0 all of it falls on the street line - flat
  /// rain, for a scene looking at one thing up close.
  double nearest = 1;

  /// The depth the eye is focused at: drops there are drawn sharp, and the
  /// farther a drop is from it - nearer the eye or farther off - the more it
  /// is out of focus. 0 is the street line, where a game's walker usually is.
  double focusDepth = 0;

  /// How out of focus the rest of the rain is: the blur, in world units per
  /// metre, of a drop whose perspective differs from the focused depth's by
  /// one. A thin lens blurs a point at distance z to a disc that grows with
  /// |1/z - 1/z_focus|, and the perspective is 1/z, so the blur is this times
  /// the difference in perspective. The light of a blurred streak spreads
  /// over its wider width, so it is fainter by as much as it is wider. 0, the
  /// default, draws every drop sharp.
  double aperture = 0;

  /// The rain over the world [component] is in, if there is one.
  static Rain? of(Component component) =>
      Stage.maybeOf(component)?.members<Rain>().firstOrNull;

  /// Drops in the air now, and droplets of bursts.
  @visibleForTesting
  int get dropsInAir => _drops.length;
  @visibleForTesting
  int get droplets => _droplets.length;
  @visibleForTesting
  Iterable<double> get dropXs => [
    for (var i = 0; i < _drops.length; i++) _drops.x(i),
  ];
  @visibleForTesting
  Iterable<double> get dropYs => [
    for (var i = 0; i < _drops.length; i++) _drops.y(i),
  ];
  @visibleForTesting
  Iterable<Vector2> get dropVelocities => [
    for (var i = 0; i < _drops.length; i++) Vector2(_drops.vx(i), _drops.vy(i)),
  ];
  @visibleForTesting
  Iterable<({double depth, double width, double alpha})> get dropLooks => [
    for (var i = 0; i < _drops.length; i++)
      (
        depth: _drops.depth(i),
        width: _drops.width(i),
        alpha: (_drops.color[i] >>> 24) / 255,
      ),
  ];

  /// Drops landed so far, by what caught them (`null`: the bare ground).
  @visibleForTesting
  final Map<Type?, int> landed = {};

  final math.Random _random;
  final DropPool _drops = DropPool();
  final DropletPool _droplets = DropletPool();
  double _due = 0;
  bool _started = false;

  /// The view drops fall over, and where a drop at a depth lands.
  ({
    Rect view,
    double Function(double depth) land,
    double Function(double depth) scale,
  })?
  _frame() {
    final stage = this.stage;
    if (stage == null) {
      return null;
    }
    // Before the stage has made its first frame, the camera's view.
    final game = findGame();
    final view = stage.frame.index > 0
        ? stage.frame.view
        : (game is FlameGame ? game.camera.visibleWorldRect : _lastView);
    if (view == null) {
      return null;
    }
    _lastView = view;
    final projection = stage.projection;
    return (
      view: view,
      // Where a drop at its depth meets the ground, and how much faster than
      // on the street line it crosses the view: the street's projection.
      // Behind the street line it ends at the line, behind whatever stands
      // there.
      land: projection == null ? (_) => view.bottom : projection.yAt,
      scale: projection == null ? _plainScale : projection.scaleAt,
    );
  }

  /// A drop's streak in focus: thicker for a nearer, heavier drop.
  double _sharpWidth(double depth, double strength) => math.max(
    (0.016 + 0.028 * depth * (0.6 + 0.4 * strength)) * metre,
    0.002 * metre,
  );

  /// With no ground: speed on the screen as one over the distance, the
  /// nearest drops two and a half times as fast as on the street line.
  static double _plainScale(double depth) => 1 / (1 - 0.6 * depth);

  Rect? _lastView;

  /// How fast the view moves across the world, world units a second: a
  /// camera following someone. A drop takes seconds from the cloud, and the
  /// view has moved on by the time it lands.
  double _viewSpeed = 0;
  double? _viewLeft;

  /// Follows the view's movement over [dt], smoothed over a fraction of a
  /// second; a jump (a restart, a seek) is not the camera moving.
  void _trackView(Rect view, double dt) {
    final previous = _viewLeft;
    _viewLeft = view.left;
    if (previous == null || dt <= 0) {
      return;
    }
    final moved = view.left - previous;
    if (moved.abs() >= view.width) {
      return;
    }
    _viewSpeed += (moved / dt - _viewSpeed) * (1 - math.exp(-dt / 0.3));
  }

  /// How much more ground than the view the rain has to reach: as far as
  /// the view travels while a drop falls the whole way down, and as far as
  /// the wind carries a drop while it falls through the view.
  double _viewReach(Rect view, double Function(double) land) {
    final top = cloudTop?.call() ?? view.top - _margin;
    final fall = RainDrops.terminalSpeed(2) * metre;
    final way = math.max(land(0) - _start(view, top), 0) / fall;
    final through = _inViewTime(view, top, land(0), fall);
    return _viewSpeed.abs() * way +
        (_windXAt(view.center.dx, view.center.dy) * metre * through).abs();
  }

  /// Where drops start: over the view, not at the cloud. Above the view a
  /// drop is unseen, and a cloud is far higher than a view is tall, so most
  /// of a drop's way down would be simulated for nothing; a drop instead
  /// starts a margin over the view, where and as fast as it would be had it
  /// fallen from the cloud.
  double _start(Rect view, double top) => math.max(top, view.top - _margin);

  /// Where drops started last step.
  double _startY = double.infinity;

  /// Fills the air between [from] and [to] (world y, [from] the start over
  /// the view) with the drops that would be there had the rain been falling
  /// all along: released over as long as the slowest drop takes down, each
  /// as far on as it would be by now, those outside the band or already
  /// down left out. Small and far drops cross the view more slowly than a
  /// 2 mm one and so hang in the air longer.
  void _fill(
    Rect view,
    double Function(double) land,
    double Function(double) scale,
    double from,
    double to,
  ) {
    final lowest = math.max(land(behind), land(nearest));
    final slowest =
        RainDrops.terminalSpeed(RainDrops.minMm) *
        metre *
        math.min(scale(behind), scale(nearest));
    final longest = math.max(math.min(lowest, to) - from, 0) / slowest;
    final released = (density * view.width / metre * intensity * longest)
        .round();
    for (var k = 0; k < released; k++) {
      final i = _newDrop(view, land, scale, 0);
      final age = _random.nextDouble() * longest;
      final fall = _drops.fall(i);
      final way = (_drops.land(i) - _drops.y(i)) / fall;
      final y = _drops.y(i) + fall * age;
      if (age >= way || y >= to || !_released(i)) {
        _drops.removeAt(i);
        continue;
      }
      _drops
        ..setX(i, _drops.x(i) + _drops.vx(i) * age)
        ..setY(i, y);
    }
  }

  /// How long a drop falling at [fall] from [top] to [landing] is inside the
  /// view's height.
  double _inViewTime(Rect view, double top, double landing, double fall) =>
      math.max(landing - math.max(view.top, top), 0) / fall;

  final Vector2 _at = Vector2.zero();
  final Vector2 _air = Vector2.zero();

  /// The wind's x at ([x], [y]), metres per second.
  double _windXAt(double x, double y) {
    final field = windAt;
    if (field == null) {
      return wind.x;
    }
    field(_at..setValues(x, y), _air);
    return _air.x;
  }

  /// How far past the view drops are born and kept, world units: a metre,
  /// so the wind carries them into the view rather than they pop in.
  double get _margin => metre;

  /// A new drop over [view], spread over the way it falls in [lead]
  /// seconds; its index.
  int _newDrop(
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
    final fallTime = math.max(landing - top, 0) / fall;
    final start = _start(view, top);
    // It lands over the view as it is now or as it will be by then: a view
    // following someone moves on while the drop falls, and rain aimed only
    // where it is now would leave its leading side dry.
    final ahead = _viewSpeed * math.max(landing - start, 0) / fall;
    // And a drop seen in the view now may still have far to go downwind:
    // one that lands past the view's downwind edge crosses it on the way
    // down, as far in as the wind carries it while it falls through the view.
    final downwind =
        _windXAt(view.center.dx, view.center.dy) *
        metre *
        _inViewTime(view, top, landing, fall) *
        perspective;
    final from =
        view.left - _margin + math.min(0, ahead) + math.min(0, downwind);
    final to =
        view.right + _margin + math.max(0, ahead) + math.max(0, downwind);
    final target = from + _random.nextDouble() * (to - from);
    final windX = _windXAt(target, (top + landing) / 2) * metre;
    final born = target - windX * perspective * fallTime;
    // Where it is as it reaches the start over the view.
    final drift = windX * perspective * math.max(start - top, 0) / fall;
    final strength = ((diameter - RainDrops.minMm) / 2.5).clamp(0.25, 1.0);
    final i = _drops.add();
    _drops
      ..setSource(i, born)
      ..setX(i, born + drift)
      // Spread over the way it falls in this step: drops born in one step
      // at one height would fall as a line.
      ..setY(i, start - _random.nextDouble() * fall * lead)
      ..setVx(i, windX * perspective)
      ..setVy(i, fall)
      ..setLand(i, landing)
      ..setDepth(i, depth)
      ..setPerspective(i, perspective)
      ..setResponse(i, RainDrops.responseSec(terminal))
      ..setFall(i, fall)
      ..setDiameter(i, diameter)
      ..setStrength(i, strength)
      ..setSharpWidth(i, _sharpWidth(depth, strength))
      ..setWidth(i, _sharpWidth(depth, strength));
    return i;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final frame = _frame();
    if (frame == null) {
      return;
    }
    final (:view, :land, :scale) = frame;
    _heardSeconds += dt;
    _heardFrom = stage?.frame.projection;
    _veil.update(this, view, dt);
    _trackView(view, dt);
    final top = cloudTop?.call() ?? view.top - _margin;
    final start = _start(view, top);
    if (!_started) {
      _started = true;
      // The rain is already falling when the scene opens.
      _fill(view, land, scale, start, double.infinity);
    } else if (start < _startY - 1e-6) {
      // The view reaches higher than it did (it grew, or rose): the air it
      // now shows over the old start holds drops already.
      _fill(view, land, scale, start, _startY);
    }
    _startY = start;
    // As many per metre over the ground the view will cross, not only the
    // view.
    _due +=
        dt *
        density *
        (view.width + _viewReach(view, land)) /
        metre *
        intensity;
    while (_due >= 1) {
      _due -= 1;
      final i = _newDrop(view, land, scale, dt);
      if (!_released(i)) {
        _drops.removeAt(i);
      }
    }
    _fallAll(view, dt);
    _droplets.step(dt, 18 * metre);
    _shade();
  }

  final Vector2 _from = Vector2.zero();
  final Vector2 _to = Vector2.zero();
  final Vector2 _velocity = Vector2.zero();

  /// Moves every drop on by [dt]: it takes up the wind where it is as fast
  /// as its size lets it, may bounce off a deflector or land on a catcher,
  /// and goes once it has crossed the view with the wind - one still on its
  /// way into it (born upwind, far off in a strong wind) stays.
  void _fallAll(Rect view, double dt) {
    final stage = this.stage!;
    final catchers = stage.members<RainCatcher>();
    final deflectors = stage.members<RainDeflector>();
    for (final catcher in catchers) {
      catcher.prepareCatch();
    }
    final field = windAt;
    final pool = _drops;
    var i = 0;
    while (i < pool.length) {
      final x = pool.x(i);
      final y = pool.y(i);
      if (field == null) {
        _air.setFrom(wind);
      } else {
        field(_at..setValues(x, y), _air);
      }
      final k = RainDrops.follow(dt, pool.response(i));
      final perspective = pool.perspective(i);
      var vx = pool.vx(i);
      var vy = pool.vy(i);
      vx += (_air.x * metre * perspective - vx) * k;
      vy += (pool.fall(i) + _air.y * metre - vy) * k;
      _from.setValues(x, y);
      _to.setValues(x + vx * dt, y + vy * dt);
      _velocity.setValues(vx, vy);
      final gone = !_deflect(i, deflectors) && _catch(i, _from.y, catchers);
      if (gone ||
          (_velocity.x >= 0
              ? _to.x > view.right + 4 * _margin
              : _to.x < view.left - 4 * _margin)) {
        pool.removeAt(i);
        continue;
      }
      pool
        ..setX(i, _to.x)
        ..setY(i, _to.y)
        ..setVx(i, _velocity.x)
        ..setVy(i, _velocity.y);
      i++;
    }
  }

  /// Whether the cloud lets drop [i] go, judged where it left the cloud.
  bool _released(int i) {
    final share = releaseShare;
    return share == null || _random.nextDouble() < share(_drops.source(i));
  }

  /// Whether a deflector on drop [i]'s way from [_from] to [_to] turned it
  /// back (moving [_to] and [_velocity] as it says).
  bool _deflect(int i, List<RainDeflector> deflectors) {
    for (final deflector in deflectors) {
      final speed = _velocity.length;
      if (deflector.deflect(_from, _to, _velocity, _drops.depth(i))) {
        // Heard once, as it falls on it; flying off, it may touch it again.
        if (!_drops.bounced(i)) {
          _drops.setBounced(i);
          _bounces++;
          _bounceSpeed += speed;
          _bounceLoudness += deflector.surface.loudness;
          _heard(
            i,
            deflector.surface,
            _from.x,
            _from.y,
            speed,
            atDepth: deflector.standsAtDepth,
          );
        }
        return true;
      }
    }
    return false;
  }

  /// Whether a catcher (or the ground) stopped drop [i], now at [_to], on
  /// its way down from [fromY]: the first on the way takes it.
  bool _catch(int i, double fromY, List<RainCatcher> catchers) {
    final x = _to.x;
    final y = _to.y;
    final depth = _drops.depth(i);
    RainCatcher? by;
    var at = double.infinity;
    for (final c in catchers) {
      final front = c.frontDepth;
      if (front != null && depth >= front) {
        // It falls in front of this one.
        continue;
      }
      final caught = c.catchDrop(x, fromY, y, depth);
      if (caught == null) {
        continue;
      }
      if (caught < at ||
          (caught == at && by != null && c.catchOrder > by.catchOrder)) {
        at = caught;
        by = c;
      }
    }
    if (by == null) {
      final land = _drops.land(i);
      if (y < land) {
        return false;
      }
      landed.update(null, (n) => n + 1, ifAbsent: () => 1);
      _heard(i, ground, x, land, _velocity.length);
      // The bare ground; behind the street line, nothing to see.
      if (depth >= 0) {
        _burst(i, x, land, ground);
      }
      return true;
    }
    landed.update(by.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    _heard(i, by.surface, x, at, _velocity.length);
    _burst(i, x, at, by.surface);
    by.onDrop(Vector2(x, at), _drops.strength(i));
    return true;
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

  /// Drop [i] bursting at ([x], [y]) on [on], if it hits hard enough to
  /// splash there: a few droplets thrown up and out, more the harder it hits,
  /// higher for a near, heavy drop. A fine drop only wets.
  void _burst(int i, double x, double y, Substance on) {
    final depth = _drops.depth(i);
    final speed = _velocity.length / (metre * _drops.perspective(i));
    final k = impactNumber(_drops.diameter(i), speed);
    final splashAbove = on.splashAbove;
    if (k <= splashAbove) {
      return;
    }
    final size = (0.5 + 0.5 * depth) * _drops.strength(i);
    final count = (1 + 2 * (k / splashAbove - 1) + size * 2).round().clamp(
      1,
      7,
    );
    for (var n = 0; n < count; n++) {
      final side = _random.nextBool() ? 1 : -1;
      _droplets.add(
        x: x,
        y: y,
        vx: side * (0.4 + 1.4 * _random.nextDouble()) * metre * size,
        vy: -(1.8 + 2.4 * _random.nextDouble()) * metre * size,
        floor: y + 0.02 * metre,
        life: 0.35,
        width: (0.02 + 0.03 * depth) * metre,
        depth: depth,
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

  final LightSample _sample = LightSample();

  /// Works out how every drop and droplet looks this frame, once: the rain
  /// is drawn again in every water's reflection, and in every slice. Each
  /// gets two looks: over the lighting, as lit as it is, and under it, where
  /// the light there is laid over it and it carries only the rest. Then
  /// sorts them into the slices that draw them.
  void _shade() {
    final stage = this.stage;
    final projection = stage?.projection;
    final field = stage?.frame.light;
    final lit = field != null && field.isLit;
    final scale = projection == null ? _plainScale : projection.scaleAt;
    final focus = scale(focusDepth);
    final water = _water;
    final drops = _drops;
    for (var i = 0; i < drops.length; i++) {
      // How much of a sharp streak's light is left per unit of its width
      // once it is blurred: the light of a blurred streak spreads over its
      // wider width.
      final sharp = drops.sharpWidth(i);
      final blurred =
          sharp + aperture * (drops.perspective(i) - focus).abs() * metre;
      drops.setWidth(i, blurred);
      final focusShare = blurred <= 0 ? 1.0 : sharp / blurred;
      final speed = math.sqrt(
        drops.vx(i) * drops.vx(i) + drops.vy(i) * drops.vy(i),
      );
      // A drop is seen by the light it throws to the eye - from the lamps
      // round it, far more from one it is in front of - and a streak is
      // that light spread over the way it falls in an exposure: each point
      // of it lit for its diameter over its speed. A fine slow drop and a
      // heavy fast one come out alike; a fast small one is a faint line.
      final trueSpeed = math.max(speed / (metre * drops.perspective(i)), 0.5);
      final exposure = drops.diameter(i) / trueSpeed / _referenceExposure;
      final share = visibility * exposure * focusShare;
      if (!lit) {
        drops.color[i] = drops.colorUnder[i] = _argb(water, share);
        continue;
      }
      field.sample(
        drops.x(i),
        drops.y(i),
        _sample,
        inFront: projection?.ahead(drops.depth(i)) ?? 0,
        forwardScatter: 0.7,
      );
      final tint = _sample.added * 0.8;
      // Under the lighting it is multiplied by what the lighting shows
      // there (LightField.fill): it carries the rest.
      final under = math.max(_sample.shown, 0.02);
      drops
        ..color[i] = _tinted(water, tint, share * _sample.scattered)
        ..colorUnder[i] = _tinted(
          water,
          tint,
          share * _sample.scattered / under,
        );
    }
    final droplets = _droplets;
    for (var i = 0; i < droplets.length; i++) {
      final sharp = droplets.width(i);
      final blurred =
          sharp + aperture * (scale(droplets.depth(i)) - focus).abs() * metre;
      droplets.setDrawnWidth(i, blurred);
      final focusShare = blurred <= 0 ? 1.0 : sharp / blurred;
      if (!lit) {
        droplets.color[i] = droplets.colorUnder[i] = _argb(
          water,
          0.9 * focusShare,
        );
        continue;
      }
      field.sample(
        droplets.x(i),
        droplets.y(i),
        _sample,
        inFront: projection?.ahead(droplets.depth(i)) ?? 0,
      );
      final light = _sample.shown;
      final tint = _sample.added * 0.8;
      droplets
        ..color[i] = _tinted(water, tint, 0.9 * light * focusShare)
        ..colorUnder[i] = _tinted(water, tint, 0.9 * focusShare);
    }
    _sort();
  }

  Color get _water => color;

  /// [c] at [alpha] times its own, as ARGB.
  static int _argb(Color c, double alpha) {
    final a = (c.a * alpha).clamp(0.0, 1.0);
    return ((a * 255).round() << 24) |
        ((c.r * 255).round() << 16) |
        ((c.g * 255).round() << 8) |
        (c.b * 255).round();
  }

  /// [c] taking [share] of the light's colour ([_sample]'s), at [alpha].
  int _tinted(Color c, double share, double alpha) {
    final t = share.clamp(0.0, 1.0);
    final r = c.r + (_sample.red - c.r) * t;
    final g = c.g + (_sample.green - c.g) * t;
    final b = c.b + (_sample.blue - c.b) * t;
    final a = (c.a * alpha).clamp(0.0, 1.0);
    return ((a * 255).round() << 24) |
        ((r.clamp(0.0, 1.0) * 255).round() << 16) |
        ((g.clamp(0.0, 1.0) * 255).round() << 8) |
        (b.clamp(0.0, 1.0) * 255).round();
  }

  /// The slices drawing this rain, each with the drops and droplets in its
  /// depths this frame.
  final List<RainSlice> _slices = [];

  /// Sorts the drops and droplets into the slices that draw them, once a
  /// frame rather than in every draw.
  void _sort() {
    for (final slice in _slices) {
      slice._drops.length = 0;
      slice._droplets.length = 0;
      for (var i = 0; i < _drops.length; i++) {
        final d = _drops.depth(i);
        if (d >= slice.from && d < slice.to) {
          slice._drops.add(i);
        }
      }
      for (var i = 0; i < _droplets.length; i++) {
        final d = _droplets.depth(i);
        if (d >= slice.from && d < slice.to) {
          slice._droplets.add(i);
        }
      }
    }
  }

  /// Whether what [drawer] draws lies under the lighting: it is below the
  /// stage's lighting among its siblings.
  bool _underLighting(Component drawer) {
    final lighting = stage?.members<Lighting>().firstOrNull;
    return lighting != null &&
        lighting.parent == drawer.parent &&
        drawer.priority < lighting.priority;
  }

  final RainVeil _veil = RainVeil();
  final RainStreaks _streaks = RainStreaks();

  /// Whether it draws itself; off when [RainSlice]s draw it by depth, each
  /// in its own place among the components.
  bool drawsItself = true;

  @override
  void render(Canvas canvas) {
    if (drawsItself) {
      renderDepths(canvas, underLighting: _underLighting(this));
    }
  }

  /// Draws the drops and droplets falling at depths from [from] up to (not
  /// including) [to], and the veils there; [underLighting] when the
  /// lighting is laid over them.
  void renderDepths(
    Canvas canvas, {
    double from = double.negativeInfinity,
    double to = double.infinity,
    bool underLighting = false,
  }) => _render(canvas, from, to, underLighting, null);

  void _render(
    Canvas canvas,
    double from,
    double to,
    bool underLighting,
    RainSlice? slice,
  ) {
    final mirror = ReflectionPass.current;
    // In water, the rain is as dark as the water it is mirrored in.
    final dark = mirror == null ? underLighting : _underLighting(mirror.drawer);
    final view = _lastView;
    final projection = stage?.projection;
    if (view != null && projection != null) {
      // The veils in water too: the way to what water mirrors crosses the
      // same air, and more of it.
      for (final depth in veils) {
        if (depth >= from && depth < to) {
          _veil.render(
            canvas,
            this,
            view,
            projection,
            depth,
            nearest: depth == veils.reduce(math.max),
          );
        }
      }
    }
    _streaks.draw(
      canvas,
      _drops,
      _droplets,
      dropRows: slice?._drops,
      dropletRows: slice?._droplets,
      from: from,
      to: to,
      under: dark,
      mirror: mirror,
      margin: _margin,
      metre: metre,
    );
  }
}

/// The rain falling in a range of depths, drawn where this sits among the
/// components: rain behind the street line under what stands on it, the
/// rest over it. Set the rain's `drawsItself` off and give it one slice for
/// each range. Water mirrors a slice as it mirrors the rain. A slice below
/// the lighting among its siblings has the lighting laid over it, and its
/// drops are drawn for that.
class RainSlice extends Component with Reflectable, OnStage, AtDepth {
  RainSlice(
    this.rain, {
    this.from = double.negativeInfinity,
    this.to = double.infinity,
    super.priority,
  }) : placedByDepth = priority == null;

  /// Placed at its depth unless given a priority outright.
  @override
  final bool placedByDepth;

  final Rain rain;

  /// The depths it draws, from [from] up to (not including) [to]: set them
  /// as what stands at those depths moves.
  double from;
  double to;

  /// It holds the drops up to its nearer edge: it is drawn at that depth,
  /// behind what stands there - or nearest of all, with no edge.
  @override
  double depthIn(StreetProjection? projection) =>
      to.isFinite ? to : double.maxFinite;

  @override
  DepthOrder get depthOrder => DepthOrder.rain;

  // The rain's drops and droplets in its depths this frame, sorted by the
  // rain while the slice is mounted.
  final List<int> _drops = [];
  final List<int> _droplets = [];

  @override
  void onMount() {
    super.onMount();
    rain._slices.add(this);
  }

  @override
  void onRemove() {
    rain._slices.remove(this);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) => rain._render(
    canvas,
    from,
    to,
    rain._underLighting(this),
    isMounted ? this : null,
  );
}

/// The drops that struck one substance ([Rain.takeImpacts]): how many, and
/// the energy the ear got from them together.
class RainStrikes {
  RainStrikes(this.on);

  /// What they struck.
  final Substance on;

  /// How many struck it.
  int count = 0;

  /// The energy the ear got from them, against a 2 mm drop at 8 m/s on a
  /// loudness-1 surface a metre off.
  double energy = 0;

  void add(double e) {
    count++;
    energy += e;
  }

  RainStrikes taken() {
    final copy = RainStrikes(on)
      ..count = count
      ..energy = energy;
    count = 0;
    energy = 0;
    return copy;
  }
}
