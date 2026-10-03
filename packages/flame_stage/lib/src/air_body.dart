import 'dart:math' as math;

import 'package:flame_stage/src/substance.dart';
import 'package:flame_stage/src/weather.dart';
import 'package:flutter/foundation.dart' show immutable;

/// What a thin flat thing the air carries is made of and how it is shaped: a
/// leaf, a scrap of paper. Its mass and size, and how the air acts on it -
/// its drag face on and edge on, the lift of the air turned round it, the
/// drag on its turning - a plate's (Andersen, Pesavento and Wang 2005).
/// Lying, how the wind gets hold of it ([restDrag]), and how much rain it
/// soaks up and sticks by ([holdsMm], [wetGripPa]).
@immutable
class AirBodyKind {
  const AirBodyKind({
    required this.name,
    required this.massKg,
    required this.chordM,
    required this.spanM,
    this.faceDrag = 1.2,
    this.edgeDrag = 0.2,
    this.circulation = 1.2,
    this.turnCirculation = math.pi,
    this.turnDrag = 0.2,
    this.restDrag = 0.3,
    this.holdsMm = 0.1,
    this.wetGripPa = 2,
    this.porosity = 0.3,
  });

  /// A broad leaf of a park tree, a lime's or a maple's: 7 by 6 cm, some
  /// 140 g a square metre as it falls (half of it water), curled so the
  /// wind gets under it lying.
  static const leaf = AirBodyKind(
    name: 'leaf',
    massKg: 0.0006,
    chordM: 0.07,
    spanM: 0.06,
    edgeDrag: 0.3,
    restDrag: 0.35,
    holdsMm: 0.15,
  );

  /// A till receipt or a torn page: 15 by 8 cm of 55 g paper, flat, so it
  /// lies close and soaks up rain until it sticks.
  static const paper = AirBodyKind(
    name: 'paper',
    massKg: 0.00066,
    chordM: 0.15,
    spanM: 0.08,
    edgeDrag: 0.15,
    restDrag: 0.2,
    holdsMm: 0.25,
    wetGripPa: 4,
    porosity: 0.6,
  );

  /// The kinds by their names.
  static const List<AirBodyKind> all = [leaf, paper];

  /// The kind called [name], or `null`.
  static AirBodyKind? named(String name) {
    for (final kind in all) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }

  /// What it is called, for data and tools.
  final String name;

  /// Its mass dry, kg.
  final double massKg;

  /// How long it is from the edge that leads to the one that trails, m:
  /// the way it turns about.
  final double chordM;

  /// How wide it is across that, m.
  final double spanM;

  /// Its drag coefficient meeting the air face on (about 1.2 for a plate).
  final double faceDrag;

  /// Its drag coefficient meeting the air edge on: skin friction and the
  /// curl of its edges.
  final double edgeDrag;

  /// The lift of the air turned round it as it meets the air aslant (their
  /// C_T, 1.2 for a long plate): what sends it gliding off toward the edge
  /// that leads. A leaf is short across: the air slips round its ends, and
  /// it gets as much less as a wing of its aspect does ([liftShare]).
  final double circulation;

  /// The lift of the air it turns round itself as it spins (their C_R, pi):
  /// what carries a tumbling strip on sideways.
  final double turnCirculation;

  /// How the air drags on its turning (their mu, 0.2): what keeps a leaf
  /// swaying rather than tumbling.
  final double turnDrag;

  /// The drag coefficient of the wind on it lying flat: what gets under its
  /// edges and its curl.
  final double restDrag;

  /// How much rain it soaks up, mm over its face.
  final double holdsMm;

  /// How hard it sticks to the ground soaked through, newtons a square
  /// metre: the water film between them.
  final double wetGripPa;

  /// How porous it is, `0..1`: how much darker it goes as it soaks (a
  /// waxed leaf little, paper much).
  final double porosity;

  /// Its face, m2.
  double get areaM2 => chordM * spanM;

  /// The share of a long plate's lift it gets, being only [spanM] across:
  /// a wing's lift slope over 2 pi for its aspect (Helmbold).
  double get liftShare {
    final aspect = spanM / chordM;
    return aspect / (2 + math.sqrt(aspect * aspect + 4));
  }

  @override
  bool operator ==(Object other) => other is AirBodyKind && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// How the air moves somewhere, m/s: along the road, ahead (away from the
/// street line toward the eye) and up. Filled in place, as a body's wind is
/// asked for every step.
class AirVelocity {
  double along = 0;
  double ahead = 0;
  double up = 0;

  void set(double along, double ahead, double up) {
    this.along = along;
    this.ahead = ahead;
    this.up = up;
  }
}

/// How turbulent the air is somewhere: how far its eddies stray from the
/// mean wind (m/s, along and across the ground, and up) and how long one
/// lasts (s).
class AirStir {
  const AirStir({
    required this.sigma,
    required this.sigmaUp,
    required this.timeSec,
  });

  /// Still air: no eddies.
  static const AirStir still = AirStir(sigma: 0, sigmaUp: 0, timeSec: 1);

  /// The eddies of the air near the ground in a wind of [meanSpeed] (m/s)
  /// at [height] (m) over ground of [roughnessM] (its roughness length: a
  /// lawn some centimetres, a town street half a metre, water a fraction
  /// of a millimetre). The ground drags on the wind: its friction velocity
  /// is k U / ln(z / z0); the eddies stray 2.4 times that along the ground
  /// and 1.25 up (Panofsky and Dutton), and last about half the height over
  /// their upward spread (Hanna). Below a couple of roughness lengths the
  /// air is taken as at that height.
  factory AirStir.nearGround({
    required double meanSpeed,
    required double height,
    required double roughnessM,
  }) {
    final z0 = math.max(roughnessM, 1e-5);
    final z = math.max(height, 2 * z0 + 0.1);
    final friction = _karman * meanSpeed.abs() / math.log(z / z0);
    final up = 1.25 * friction;
    return AirStir(
      sigma: 2.4 * friction,
      sigmaUp: up,
      timeSec: up <= 0 ? 1 : 0.5 * z / up,
    );
  }

  /// Von Karman's constant.
  static const double _karman = 0.4;

  /// The height a scene's wind is given at, m: where a walker holds an
  /// umbrella.
  static const double referenceM = 2;

  /// The share of the wind at [referenceM] (m) that blows at [height] (m)
  /// over a surface of roughness length [surfaceM]: the logarithmic wind of
  /// the surface layer, ln(z / z0) / ln(zr / z0) - a third of it a couple
  /// of centimetres over a road, nothing in the grass. Above the reference,
  /// all of it.
  static double windShare({
    required double height,
    required double surfaceM,
    double referenceM = AirStir.referenceM,
  }) {
    final z0 = math.max(surfaceM, 1e-5);
    if (height >= referenceM) {
      return 1;
    }
    if (height <= z0) {
      return 0;
    }
    return math.log(height / z0) / math.log(referenceM / z0);
  }

  final double sigma;
  final double sigmaUp;
  final double timeSec;
}

/// Where an [AirBody] is: in the air, lying on the ground, or floating.
enum AirBodyRest { flying, lying, floating }

/// A thin flat thing in the air or come to rest: where it is (m: along the
/// road, ahead of the street line, up), how it moves, and how it is turned -
/// it turns about its span, which lies level at [yaw] across the road, so it
/// moves and sways in the upright plane along [yaw] (0 along the road, pi/2
/// toward the eye) and slides along its span besides.
///
/// [fly] steps it through the air by its weight and the air on it; it lands
/// where the caller says the ground is. Lying, the wind lifts it once it
/// pushes harder than it holds on ([liftsIn]); afloat, the wind drifts it.
class AirBody {
  AirBody(
    this.kind, {
    required this.x,
    required this.ahead,
    required this.height,
    this.yaw = 0,
    this.angle = 0,
    this.rest = AirBodyRest.flying,
  });

  final AirBodyKind kind;

  /// Where it is, m: along the road, ahead of the street line, up.
  double x;
  double ahead;
  double height;

  /// How it moves, m/s.
  double vAlong = 0;
  double vAhead = 0;
  double vUp = 0;

  /// The way it sways in: 0 along the road, pi/2 toward the eye.
  final double yaw;

  /// How its chord is turned from level in that plane, radians, and how
  /// fast it turns.
  double angle;
  double spin = 0;

  /// Whether it flies, lies or floats.
  AirBodyRest rest;

  /// The rain in it, mm over its face.
  double waterMm = 0;

  /// The eddy of the air round it now, m/s: how the air it meets strays
  /// from the mean wind ([stir]).
  double eddyAlong = 0;
  double eddyAhead = 0;
  double eddyUp = 0;

  /// Lets the eddies round it run on [dt] seconds in air as turbulent as
  /// [air] says: each part a Langevin process - it forgets itself over the
  /// eddies' time and [random] stirs in the rest (Thomson 1987), so its
  /// spread stays the air's.
  void stir(double dt, AirStir air, math.Random random) {
    final keep = math.exp(-dt / math.max(air.timeSec, 1e-3));
    final fresh = math.sqrt(math.max(1 - keep * keep, 0));
    eddyAlong = eddyAlong * keep + air.sigma * fresh * _normal(random);
    eddyAhead = eddyAhead * keep + air.sigma * fresh * _normal(random);
    eddyUp = eddyUp * keep + air.sigmaUp * fresh * _normal(random);
  }

  /// A standard normal draw (Box-Muller).
  static double _normal(math.Random random) {
    final u = math.max(random.nextDouble(), 1e-12);
    return math.sqrt(-2 * math.log(u)) *
        math.cos(2 * math.pi * random.nextDouble());
  }

  /// How much of its colour the water in it takes away, `0..1`: as a wet
  /// surface's (`Wettable.wetDarkening`), its pores filling first.
  double get wetDarkening {
    final t = (wetness / 0.5).clamp(0.0, 1.0);
    return 0.8 * kind.porosity * t * t * (3 - 2 * t);
  }

  /// Its weight, kg, with the rain in it.
  double get massKg => kind.massKg + waterMm / 1000 * _water * kind.areaM2;

  /// How soaked it is, `0..1`.
  double get wetness =>
      kind.holdsMm <= 0 ? 0 : (waterMm / kind.holdsMm).clamp(0.0, 1.0);

  /// Gravity, m/s2.
  static const double gravity = 9.81;

  static const double _water = 1000;

  /// The density of air at [celsius] at sea level, kg/m3 (ideal gas).
  static double airDensity(double celsius) =>
      101325 / (287.05 * (celsius + 273.15));

  /// The share of the wind a leaf afloat drifts at: the wind's drift of the
  /// water's skin (about 3 %) and the little of it above the water.
  static const double floatDrift = 0.035;

  /// Steps it [dt] seconds through the air moving at [air] (m/s, the mean
  /// wind; the eddy round it, [stir], on top) of [density], by the
  /// quasi-steady model of a falling plate (Andersen, Pesavento and Wang
  /// 2005), written in its own axes - along its chord
  /// (u) and across its face (v): its weight; the air it carries along
  /// across its face, which turns it broadside to the air it meets (the
  /// Munk moment); the lift of the air turned round it, as it meets the air
  /// aslant and as it spins; the drag on it and on its turning. Along its
  /// span the air only drags.
  void fly(double dt, AirVelocity air, {double density = 1.2}) {
    if (rest != AirBodyRest.flying || dt <= 0) {
      return;
    }
    final c = kind.chordM;
    final s = kind.spanM;
    final mass = massKg;
    // The air it carries along across its face (m22; along its chord a thin
    // plate carries none) and as it turns.
    final m22 = density * math.pi * c * c / 4 * s;
    final inertia =
        mass * c * c / 12 + density * math.pi * c * c * c * c * s / 128;
    final felt = _felt
      ..set(air.along + eddyAlong, air.ahead + eddyAhead, air.up + eddyUp);
    final p = _Plate(
      kind: kind,
      air: felt,
      density: density,
      mass: mass,
      m22: m22,
      inertia: inertia,
      ex: math.cos(yaw),
      ea: math.sin(yaw),
    );
    // Steps short enough for the stiffest of it at the speed it meets the
    // air now: the Munk moment swinging it, the drag settling it, the drag
    // on its turning.
    final rx = vAlong - felt.along;
    final ra = vAhead - felt.ahead;
    final rh = vUp - felt.up;
    final speed = math.sqrt(rx * rx + ra * ra + rh * rh) + gravity * dt;
    final settle = 0.5 * density * c * s * kind.faceDrag * speed / mass;
    final swing = speed * math.sqrt(m22 / inertia);
    final turning =
        math.pi *
        density *
        c *
        c *
        c *
        c /
        16 *
        s *
        kind.turnDrag *
        spin.abs() /
        inertia;
    final rate = math.max(
      math.max(settle, swing),
      math.max(turning, spin.abs()),
    );
    final steps = (dt * rate / 0.5).ceil().clamp(1, 64);
    final h = dt / steps;
    final y = _y
      ..[0] = vAlong
      ..[1] = vAhead
      ..[2] = vUp
      ..[3] = angle
      ..[4] = spin;
    var dx = 0.0;
    var da = 0.0;
    var dh = 0.0;
    for (var i = 0; i < steps; i++) {
      // Runge-Kutta 4: the swing is an oscillation, which a plain step
      // feeds energy into.
      p.derive(y, _k1);
      for (var j = 0; j < 5; j++) {
        _t[j] = y[j] + h / 2 * _k1[j];
      }
      p.derive(_t, _k2);
      for (var j = 0; j < 5; j++) {
        _t[j] = y[j] + h / 2 * _k2[j];
      }
      p.derive(_t, _k3);
      for (var j = 0; j < 5; j++) {
        _t[j] = y[j] + h * _k3[j];
      }
      p.derive(_t, _k4);
      // Where it goes: its speed over the step, by the same weights.
      dx +=
          h /
          6 *
          (y[0] +
              2 * (y[0] + h / 2 * _k1[0]) +
              2 * (y[0] + h / 2 * _k2[0]) +
              y[0] +
              h * _k3[0]);
      da +=
          h /
          6 *
          (y[1] +
              2 * (y[1] + h / 2 * _k1[1]) +
              2 * (y[1] + h / 2 * _k2[1]) +
              y[1] +
              h * _k3[1]);
      dh +=
          h /
          6 *
          (y[2] +
              2 * (y[2] + h / 2 * _k1[2]) +
              2 * (y[2] + h / 2 * _k2[2]) +
              y[2] +
              h * _k3[2]);
      for (var j = 0; j < 5; j++) {
        y[j] += h / 6 * (_k1[j] + 2 * _k2[j] + 2 * _k3[j] + _k4[j]);
      }
    }
    vAlong = y[0];
    vAhead = y[1];
    vUp = y[2];
    angle = y[3];
    spin = y[4];
    x += dx;
    ahead += da;
    height += dh;
    if (angle > math.pi) {
      angle -= 2 * math.pi;
    } else if (angle < -math.pi) {
      angle += 2 * math.pi;
    }
  }

  static final AirVelocity _felt = AirVelocity();

  // Scratch for the steps: velocities along, ahead, up, its angle and spin.
  static final List<double> _y = List.filled(5, 0);
  static final List<double> _t = List.filled(5, 0);
  static final List<double> _k1 = List.filled(5, 0);
  static final List<double> _k2 = List.filled(5, 0);
  static final List<double> _k3 = List.filled(5, 0);
  static final List<double> _k4 = List.filled(5, 0);

  /// Brings it to rest on what it fell onto: flat on the ground, or afloat.
  void settle({required bool onWater}) {
    rest = onWater ? AirBodyRest.floating : AirBodyRest.lying;
    height = 0;
    vAlong = 0;
    vAhead = 0;
    vUp = 0;
    angle = 0;
    spin = 0;
  }

  /// Whether the wind [air] (m/s, over the ground) of [density] lifts it off
  /// [ground] it lies on: when the wind's drag on it outdoes the friction of
  /// its weight and the grip of the water under it. Lifted, its upwind edge
  /// rises and it is in the air.
  bool liftsIn(AirVelocity air, Substance ground, {double density = 1.2}) {
    if (rest != AirBodyRest.lying) {
      return false;
    }
    final w2 = air.along * air.along + air.ahead * air.ahead;
    final push = 0.5 * density * kind.restDrag * kind.areaM2 * w2;
    final hold =
        ground.friction * massKg * gravity +
        kind.wetGripPa * wetness * kind.areaM2;
    if (push <= hold) {
      return false;
    }
    rest = AirBodyRest.flying;
    // Its upwind edge up, as the wind gets under it: the edge that leads
    // into the wind, where its plane meets it.
    final along = air.along * math.cos(yaw) + air.ahead * math.sin(yaw);
    angle = along >= 0 ? -_liftTilt : _liftTilt;
    height = kind.chordM / 2 * math.sin(_liftTilt);
    return true;
  }

  /// How high over the ground lying it meets the wind, m: its curl.
  double get restHeightM => kind.chordM / 4;

  /// How far its edge is up as the wind first gets under it, radians.
  static const double _liftTilt = 0.4;

  /// Drifts it [dt] seconds afloat in the wind [air].
  void drift(double dt, AirVelocity air) {
    if (rest != AirBodyRest.floating) {
      return;
    }
    x += air.along * floatDrift * dt;
    ahead += air.ahead * floatDrift * dt;
  }

  /// Soaks it [dt] seconds in [weather]'s rain, and dries it in its air (in
  /// the world's time); afloat, it is soaked through.
  void soak(WeatherState weather, double dt, {bool sheltered = false}) {
    if (rest == AirBodyRest.floating) {
      waterMm = kind.holdsMm;
      return;
    }
    final hours = dt * weather.pace / 3600;
    if (hours <= 0) {
      return;
    }
    final gain = sheltered ? 0.0 : weather.rainMmPerHour;
    final loss = waterMm > 0 ? weather.evaporationMmPerHour : 0.0;
    waterMm = (waterMm + (gain - loss) * hours).clamp(0.0, kind.holdsMm);
  }

  /// Its corners as it is turned now, m: its middle plus or minus half its
  /// chord and half its span, round it - written into [out] from [at] as
  /// `along, ahead, up` for each (twelve numbers), as it is drawn every
  /// frame.
  void cornersInto(List<double> out, [int at = 0]) {
    final hc = kind.chordM / 2;
    final hs = kind.spanM / 2;
    final ex = math.cos(yaw);
    final ea = math.sin(yaw);
    final ct = math.cos(angle);
    final st = math.sin(angle);
    // Its chord in the plane, and its span level across it.
    final cx = hc * ct * ex;
    final ca = hc * ct * ea;
    final ch = hc * st;
    final sx = -hs * ea;
    final sa = hs * ex;
    out
      ..[at] = x + cx + sx
      ..[at + 1] = ahead + ca + sa
      ..[at + 2] = height + ch
      ..[at + 3] = x + cx - sx
      ..[at + 4] = ahead + ca - sa
      ..[at + 5] = height + ch
      ..[at + 6] = x - cx - sx
      ..[at + 7] = ahead - ca - sa
      ..[at + 8] = height - ch
      ..[at + 9] = x - cx + sx
      ..[at + 10] = ahead - ca + sa
      ..[at + 11] = height - ch;
  }
}

/// A plate's equations of motion in the air (Andersen, Pesavento and Wang
/// 2005), in its own axes - along its chord (u) and across its face (v) -
/// for one step of [AirBody.fly].
class _Plate {
  _Plate({
    required this.kind,
    required this.air,
    required this.density,
    required this.mass,
    required this.m22,
    required this.inertia,
    required this.ex,
    required this.ea,
  });

  final AirBodyKind kind;
  final AirVelocity air;
  final double density;
  final double mass;
  final double m22;
  final double inertia;
  final double ex;
  final double ea;

  /// The kinematic viscosity of air, m2/s.
  static const double _viscosity = 1.5e-5;

  /// The change of [y] (velocities along, ahead, up; angle; spin) into
  /// [out]: its weight; the air it carries across its face, which turns it
  /// broadside to the air it meets (the Munk moment); the lift of the air
  /// turned round it, aslant and spinning; the drag on it, from edge on to
  /// face on, and on its turning. Along its span the air only drags.
  void derive(List<double> y, List<double> out) {
    final c = kind.chordM;
    final s = kind.spanM;
    final angle = y[3];
    final w = y[4];
    final ct = math.cos(angle);
    final st = math.sin(angle);
    final wx = y[0] - air.along;
    final wa = y[1] - air.ahead;
    final wh = y[2] - air.up;
    // The air it meets in its plane (p along it, up), along its span, and
    // in its own axes.
    final wp = wx * ex + wa * ea;
    final ws = -wx * ea + wa * ex;
    final u = wp * ct + wh * st;
    final v = -wp * st + wh * ct;
    final speed = math.sqrt(u * u + v * v);
    // The air turned round it, per its span: aslant -Ct c u v / |V|,
    // spinning Cr c^2 w / 2.
    final gamma =
        kind.liftShare *
        ((speed <= 1e-9 ? 0.0 : -kind.circulation * c * u * v / speed) +
            kind.turnCirculation * c * c * w / 2);
    // The drag, from edge on to face on: (A - B cos 2a) |V|.
    final cos2a = speed <= 1e-9 ? 0.0 : (u * u - v * v) / (speed * speed);
    final dragMean = (kind.faceDrag + kind.edgeDrag) / 2;
    final dragSwing = (kind.faceDrag - kind.edgeDrag) / 2;
    final drag = 0.5 * density * c * s * (dragMean - dragSwing * cos2a) * speed;
    final m2 = mass + m22;
    final uDot =
        (m2 * v * w -
            density * s * gamma * v -
            mass * AirBody.gravity * st -
            drag * u) /
        mass;
    final vDot =
        (-mass * u * w +
            density * s * gamma * u -
            mass * AirBody.gravity * ct -
            drag * v) /
        m2;
    // Its turning: the Munk moment and the drag on turning,
    // pi rho (c/2)^4 s (mu nu / (c/2)^2 + mu |w|) w.
    final quarter = c * c * c * c / 16;
    final turnDrag =
        math.pi *
        density *
        quarter *
        s *
        kind.turnDrag *
        (_viscosity * 4 / (c * c) + w.abs()) *
        w;
    final wDot = (-m22 * u * v - turnDrag) / inertia;
    // Back to the road's axes: the change of its own-axis speeds plus the
    // turn of the axes themselves.
    final ap = (uDot - w * v) * ct - (vDot + w * u) * st;
    final ah = (uDot - w * v) * st + (vDot + w * u) * ct;
    final full = math.sqrt(speed * speed + ws * ws);
    final asp = -0.5 * density * c * s * kind.edgeDrag * full * ws / mass;
    out
      ..[0] = ap * ex - asp * ea
      ..[1] = ap * ea + asp * ex
      ..[2] = ah
      ..[3] = w
      ..[4] = wDot;
  }
}
