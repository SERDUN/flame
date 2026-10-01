import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
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
/// the street's ground that far towards the viewer - a far one on the line
/// things stand on, a near one low in the view - and a near drop looks
/// longer, brighter and faster. On its way it may be caught by a
/// [RainCatcher] (a roof, a puddle, the road): the first one it reaches
/// takes it, and it bursts into droplets there if the catcher splashes.
///
/// It reads everything from the stage's frame: the view, the street's
/// projection, the light. Under a `Lighting` a drop is as bright as the
/// light where it is and takes its colour, so rain shines in a lamp's cone.
/// Drawn over the night, a drop carries the night's darkness itself; drawn
/// under it ([RainSlice] below the lighting), the night darkens it, and it
/// carries only the light. [Rain.of] finds the rain over a world, for what
/// depends on it (water astir, things getting wet and drying).
class Rain extends Component with OnStage, Reflectable {
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
  /// far across as its depth on the street makes it, slanted by the
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
  Iterable<double> get dropXs => _drops.map((d) => d.at.x);
  @visibleForTesting
  Iterable<double> get dropYs => _drops.map((d) => d.at.y);
  @visibleForTesting
  Iterable<Vector2> get dropVelocities => _drops.map((d) => d.velocity);
  @visibleForTesting
  Iterable<({double depth, double width, double alpha})> get dropLooks =>
      _drops.map((d) => (depth: d.depth, width: d.width, alpha: d.color.a));

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
  double _sharpWidth(_Drop d) => math.max(
    (0.016 + 0.028 * d.depth * (0.6 + 0.4 * d.strength)) * metre,
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
        (_windX(_viewCenter(view)) * metre * through).abs();
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
    for (var i = 0; i < released; i++) {
      final drop = _newDrop(view, land, scale, 0);
      final age = _random.nextDouble() * longest;
      final way = (drop.land - drop.at.y) / drop.fall;
      final y = drop.at.y + drop.fall * age;
      if (age >= way || y >= to || !_released(drop)) {
        continue;
      }
      drop.at
        ..x += drop.velocity.x * age
        ..y = y;
      _drops.add(drop);
    }
  }

  /// How long a drop falling at [fall] from [top] to [landing] is inside the
  /// view's height.
  double _inViewTime(Rect view, double top, double landing, double fall) =>
      math.max(landing - math.max(view.top, top), 0) / fall;

  Vector2 _viewCenter(Rect view) => Vector2(view.center.dx, view.center.dy);

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
        _windX(_viewCenter(view)) *
        metre *
        _inViewTime(view, top, landing, fall) *
        perspective;
    final from =
        view.left - _margin + math.min(0, ahead) + math.min(0, downwind);
    final to =
        view.right + _margin + math.max(0, ahead) + math.max(0, downwind);
    final target = from + _random.nextDouble() * (to - from);
    final windX = _windX(Vector2(target, (top + landing) / 2)) * metre;
    final born = target - windX * perspective * fallTime;
    // Where it is as it reaches the start over the view.
    final drift = windX * perspective * math.max(start - top, 0) / fall;
    return _Drop(
      source: born,
      at: Vector2(
        born + drift,
        // Spread over the way it falls in this step: drops born in one step
        // at one height would fall as a line.
        start - _random.nextDouble() * fall * lead,
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
      final drop = _newDrop(view, land, scale, dt);
      if (_released(drop)) {
        _drops.add(drop);
      }
    }
    final catchers = stage!.members<RainCatcher>();
    final deflectors = stage!.members<RainDeflector>();
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
  /// Whether the cloud lets [d] go, judged where it left the cloud.
  bool _released(_Drop d) {
    final share = releaseShare;
    return share == null || _random.nextDouble() < share(d.source);
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
  /// is drawn again in every water's reflection, and in every slice. Each
  /// gets two looks: over the night, carrying its darkness, and under it,
  /// where the night darkens it and it carries only the light.
  void _shade() {
    final stage = this.stage;
    final projection = stage?.projection;
    final field = stage?.frame.light;
    final lit = field != null && field.isLit;
    final scale = projection == null ? _plainScale : projection.scaleAt;
    final focus = scale(focusDepth);
    // How much of a sharp streak's light is left per unit of its width once
    // it is blurred to [width].
    double sharpShare(
      double sharp,
      double perspective,
      void Function(double) width,
    ) {
      final blurred = sharp + aperture * (perspective - focus).abs() * metre;
      width(blurred);
      return blurred <= 0 ? 1 : sharp / blurred;
    }

    // What the night takes from a drop with no light on it: under the
    // night it is taken by the night layer, so the drop gives it back.
    final night = lit ? field.darkness : 0.0;
    for (final d in _drops) {
      final focusShare = sharpShare(
        _sharpWidth(d),
        d.perspective,
        (w) => d.width = w,
      );
      final speed = d.velocity.length;
      // A drop is seen by the light it throws to the eye - from the lamps
      // round it, far more from one it is in front of - and a streak is
      // that light spread over the way it falls in an exposure: each point
      // of it lit for its diameter over its speed. A fine slow drop and a
      // heavy fast one come out alike; a fast small one is a faint line.
      final trueSpeed = math.max(speed / (metre * d.perspective), 0.5);
      final exposure = d.diameter / trueSpeed / _referenceExposure;
      final share = visibility * exposure * focusShare;
      if (!lit) {
        d.color = d.colorUnder = _water.withValues(
          alpha: share.clamp(0, 1),
        );
        continue;
      }
      field.sample(
        d.at.x,
        d.at.y,
        _sample,
        inFront: projection?.ahead(d.depth) ?? 0,
        forwardScatter: 0.7,
      );
      final tinted = Color.lerp(_water, _sample.color, _sample.added * 0.8)!;
      d
        ..color = tinted.withValues(
          alpha: (share * _sample.scattered).clamp(0, 1),
        )
        ..colorUnder = tinted.withValues(
          alpha: (share * (_sample.scattered + night)).clamp(0, 1),
        );
    }
    for (final p in _droplets) {
      final focusShare = sharpShare(
        p.width,
        scale(p.depth),
        (w) => p.drawnWidth = w,
      );
      if (!lit) {
        p.color = p.colorUnder = _water.withValues(
          alpha: (0.9 * focusShare).clamp(0, 1),
        );
        continue;
      }
      field.sample(
        p.at.x,
        p.at.y,
        _sample,
        inFront: projection?.ahead(p.depth) ?? 0,
      );
      final light = _sample.light.clamp(0.0, 1.0);
      final tinted = Color.lerp(_water, _sample.color, _sample.added * 0.8)!;
      p
        ..color = tinted.withValues(
          alpha: (0.9 * light * focusShare).clamp(0, 1),
        )
        ..colorUnder = tinted.withValues(
          alpha: (0.9 * math.min(light + night, 1) * focusShare).clamp(0, 1),
        );
    }
  }

  final LightSample _sample = LightSample();

  /// Whether what [drawer] draws lies under the night: it is below the
  /// stage's lighting among its siblings.
  bool _underNight(Component drawer) {
    final lighting = stage?.members<Lighting>().firstOrNull;
    return lighting != null &&
        lighting.parent == drawer.parent &&
        drawer.priority < lighting.priority;
  }

  // The streaks and droplets as triangles: one draw for the whole rain.
  Float32List _positions = Float32List(0);
  Int32List _colors = Int32List(0);
  final Paint _paint = Paint();

  /// The veil at [depth]: haze, streaks, and at the nearest veil the spray.
  void _renderVeil(Canvas canvas, double depth) {
    final view = _lastView;
    final projection = stage?.projection;
    final rain = intensity.clamp(0.0, 2.5);
    if (view == null || projection == null || rain <= 0.01) {
      return;
    }
    final scale = projection.scaleAt(depth);
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
        final line = projection.yAt(0);
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
      renderDepths(canvas, underNight: _underNight(this));
    }
  }

  /// Draws the drops and droplets falling at depths from [from] up to (not
  /// including) [to]; [underNight] when the night is drawn over them.
  void renderDepths(
    Canvas canvas, {
    double from = double.negativeInfinity,
    double to = double.infinity,
    bool underNight = false,
  }) {
    final mirror = ReflectionPass.current;
    // In water, the rain is as dark as the water it is mirrored in.
    final dark = mirror == null ? underNight : _underNight(mirror.drawer);
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
    // triangles are not. Four triangles, twelve vertices; out of focus, four
    // more fade its ends out over the blur.
    if (_positions.length < quads * 48) {
      _positions = Float32List(quads * 48 * 2);
      _colors = Int32List(quads * 24 * 2);
    }
    var v = 0;
    var c = 0;
    void point(double x, double y, int argb) {
      _positions[v++] = x;
      _positions[v++] = y;
      _colors[c++] = argb;
    }

    void quad(
      double hx,
      double hy,
      double tx,
      double ty,
      double w,
      int argb, {
      double blur = 0,
    }) {
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
      if (blur > 1e-6 && len >= 1e-6) {
        // Out of focus the ends are as soft as the sides: each runs out to
        // clear over the blur, past the head and behind the tail.
        final ux = (hx - tx) / len * blur;
        final uy = (hy - ty) / len * blur;
        for (final s in const [-1.0, 1.0]) {
          point(hx + s * nx, hy + s * ny, clear);
          point(hx, hy, argb);
          point(hx + ux, hy + uy, clear);
          point(tx + s * nx, ty + s * ny, clear);
          point(tx, ty, argb);
          point(tx - ux, ty - uy, clear);
        }
      }
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
        d.width,
        (dark ? d.colorUnder : d.color).toARGB32(),
        blur: d.width - _sharpWidth(d),
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
        y - p.drawnWidth / 2,
        p.at.x,
        y + p.drawnWidth / 2,
        p.drawnWidth,
        (dark ? p.colorUnder : p.color).toARGB32(),
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
    required this.source,
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

  /// World x where it left the cloud.
  final double source;

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

  /// How it looks this frame, over the night and under it.
  Color color = const Color(0x00000000);
  Color colorUnder = const Color(0x00000000);

  /// Its streak's width this frame, blurred as far as it is out of focus.
  double width = 0;
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

  /// Its width as drawn this frame, blurred as far as it is out of focus.
  double drawnWidth = 0;

  /// How it looks this frame, over the night and under it.
  Color color = const Color(0x00000000);
  Color colorUnder = const Color(0x00000000);
}

/// The rain falling in a range of depths, drawn where this sits among the
/// components: rain behind the street line under what stands on it, the
/// rest over it. Set the rain's `drawsItself` off and give it one slice for
/// each range. Water mirrors a slice as it mirrors the rain. A slice below
/// the lighting among its siblings is under the night, and its drops are
/// drawn for that.
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
  void render(Canvas canvas) => rain.renderDepths(
    canvas,
    from: from,
    to: to,
    underNight: rain._underNight(this),
  );
}
