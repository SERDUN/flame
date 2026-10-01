import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/src/shadow.dart';
import 'package:flame_stage/src/stage.dart';
import 'package:flame_stage/src/street_projection.dart';

/// What shape a light gives off from.
enum LightShape {
  /// A bulb: all round.
  point,

  /// A street lamp, a headlight, a torch: a cone along [Light.direction].
  cone,

  /// A shop window, a lit sign, a doorway: a glowing rectangle
  /// [Light.extent] big, lighting what is in front of it.
  area,

  /// A neon tube, a strip light: a glowing segment [Light.extent].x long
  /// along [Light.direction].
  line,

  /// The moon, an overcast sky: from no place in view, the same everywhere.
  directional,
}

/// How a light falls off with distance.
enum Falloff {
  /// Smoothly to nothing at [Light.radius]: a lamp lighting a stretch of
  /// street, gone beyond it. Cheap and bounded.
  smooth,

  /// As light does, with the square of distance, reaching 1 at
  /// [Light.radius] / 4 and cut to nothing at [Light.radius]: a hard bright
  /// heart and a long faint reach.
  physical,
}

/// One light, as a component carries it ([LightCarrier]).
///
/// Everything about it can change at any time; the stage reads it once a
/// frame into the [LightField]. Its [intensity] is not capped at 1: an HDR
/// light buffer keeps what is brighter than white, the canvas clamps it.
class Light {
  Light({
    this.shape = LightShape.point,
    Vector2? offset,
    this.depth = 0,
    this.color = const Color(0xFFFFD9A0),
    this.intensity = 1,
    this.radius = 120,
    this.falloff = Falloff.smooth,
    this.direction = math.pi / 2,
    this.spread = math.pi,
    this.softEdge = 0.65,
    Vector2? extent,
    this.sourceRadius = 6,
    this.flicker = 0,
    this.seed = 0,
    this.dimmer = 1,
    this.onAtDarkness,
    this.standsAt,
    this.spill = 0,
    this.spillRadius = 0,
  }) : offset = offset ?? Vector2.zero(),
       extent = extent ?? Vector2.zero();

  /// A bulb.
  Light.point({
    Vector2? offset,
    double depth = 0,
    Color color = const Color(0xFFFFD9A0),
    double intensity = 1,
    double radius = 120,
    Falloff falloff = Falloff.smooth,
    double sourceRadius = 6,
    double flicker = 0,
    int seed = 0,
    double? onAtDarkness,
  }) : this(
         offset: offset,
         depth: depth,
         color: color,
         intensity: intensity,
         radius: radius,
         falloff: falloff,
         sourceRadius: sourceRadius,
         flicker: flicker,
         seed: seed,
         onAtDarkness: onAtDarkness,
       );

  /// A street lamp shining down, a headlight, a torch: [spread] radians
  /// wide along [direction] (y down: pi / 2 is straight down).
  Light.cone({
    Vector2? offset,
    double depth = 0,
    Color color = const Color(0xFFFFD9A0),
    double intensity = 1,
    double radius = 120,
    double direction = math.pi / 2,
    double spread = 1.2,
    double softEdge = 0.65,
    Falloff falloff = Falloff.smooth,
    double sourceRadius = 6,
    double flicker = 0,
    int seed = 0,
    double? onAtDarkness,
    double spill = 0,
    double spillRadius = 0,
  }) : this(
         shape: LightShape.cone,
         offset: offset,
         depth: depth,
         color: color,
         intensity: intensity,
         radius: radius,
         direction: direction,
         spread: spread,
         softEdge: softEdge,
         falloff: falloff,
         sourceRadius: sourceRadius,
         flicker: flicker,
         seed: seed,
         onAtDarkness: onAtDarkness,
         spill: spill,
         spillRadius: spillRadius,
       );

  /// A glowing rectangle [size] big centred on [offset]: a shop window, a
  /// lit sign.
  Light.area({
    required Vector2 size,
    Vector2? offset,
    double depth = 0,
    Color color = const Color(0xFFFFD9A0),
    double intensity = 1,
    double radius = 120,
    Falloff falloff = Falloff.smooth,
    double flicker = 0,
    int seed = 0,
    double? onAtDarkness,
  }) : this(
         shape: LightShape.area,
         offset: offset,
         depth: depth,
         color: color,
         intensity: intensity,
         radius: radius,
         falloff: falloff,
         extent: size,
         sourceRadius: 0,
         flicker: flicker,
         seed: seed,
         onAtDarkness: onAtDarkness,
       );

  /// A glowing tube [length] long along [direction] through [offset].
  Light.line({
    required double length,
    Vector2? offset,
    double depth = 0,
    double direction = 0,
    Color color = const Color(0xFFFFD9A0),
    double intensity = 1,
    double radius = 120,
    Falloff falloff = Falloff.smooth,
    double flicker = 0,
    int seed = 0,
    double? onAtDarkness,
  }) : this(
         shape: LightShape.line,
         offset: offset,
         depth: depth,
         direction: direction,
         color: color,
         intensity: intensity,
         radius: radius,
         falloff: falloff,
         extent: Vector2(length, 0),
         sourceRadius: 0,
         flicker: flicker,
         seed: seed,
         onAtDarkness: onAtDarkness,
       );

  /// Light from no place in view, the same everywhere: the moon, a glowing
  /// overcast sky.
  Light.directional({
    Color color = const Color(0xFFB8C8FF),
    double intensity = 0.2,
    double direction = math.pi / 2,
  }) : this(
         shape: LightShape.directional,
         color: color,
         intensity: intensity,
         direction: direction,
         sourceRadius: 0,
       );

  LightShape shape;

  /// Where on its carrier it is, in the carrier's own coordinates (for a
  /// carrier that is not a `PositionComponent`, world coordinates).
  Vector2 offset;

  /// The street depth it stands at (see [StreetProjection]): 0 on the street
  /// line, toward 1 nearer the eye, below 0 behind. Light reaching rain or
  /// ground at another depth goes that much farther.
  double depth;

  Color color;

  /// How bright: 1 lifts the night fully at its heart; above 1 is brighter
  /// than white, which only an HDR light buffer keeps.
  double intensity;

  /// How far it reaches, world units.
  double radius;

  Falloff falloff;

  /// Its axis, radians from +x, y down: a cone's beam, a tube's length.
  double direction;

  /// A cone's full angle, radians.
  double spread;

  /// The share of a cone's light its source throws all round, near it: a
  /// street lamp's bulb lights its own head and the air round it, not only
  /// the street under the cone. 0 a cone and nothing else.
  double spill;

  /// How far round the source [spill] reaches, world units.
  double spillRadius;

  /// Share of a cone's half angle, at its edge, over which it eases out.
  double softEdge;

  /// An area's width and height; a line's length in x.
  Vector2 extent;

  /// How big what glows itself is - a bulb, a tube - world units: water
  /// mirrors it as a bright spot, wet air haloes it.
  double sourceRadius;

  /// How much it flickers, `0..1`: a failing tube, a candle.
  double flicker;

  /// Where it is in its flicker.
  int seed;

  /// A switch and a dimmer for whoever runs it, `0..1`.
  double dimmer;

  /// If set, it comes on as the night falls: off in the day, fully on once
  /// the scene's darkness reaches this - lamps that light themselves.
  double? onAtDarkness;

  /// World y of the ground it stands on, if water should mirror it about
  /// there rather than about its depth's ground line.
  double? standsAt;

  /// How bright it is now, at [time] seconds and the scene's [darkness].
  double strengthAt(double time, double darkness) {
    var s = intensity * dimmer;
    final on = onAtDarkness;
    if (on != null) {
      s *= on <= 0 ? 1 : (darkness / on).clamp(0.0, 1.0);
    }
    if (flicker > 0) {
      final t = time * 9 + seed * 1.618;
      final wobble = 0.5 + 0.25 * math.sin(t) + 0.25 * math.sin(t * 2.7 + 1.3);
      s *= 1 - flicker * wobble;
    }
    return s;
  }
}

/// A component that carries lights: a lamp post, a lit window, a walker's
/// torch, a car's headlights. The stage reads its [lights] once a frame,
/// where they are on it now. On the stage it is [OnStage]: a carrier off it
/// would light nothing, so the type asks for it.
mixin LightCarrier on OnStage {
  /// Its lights now.
  Iterable<Light> get lights;
}

/// What the night is like: the scene's darkness, the colour of the dark,
/// the haze that haloes lights, how much colour lights add. One a scene
/// (the lighting); none means day.
mixin Ambience on OnStage {
  /// How dark it is where no light falls, `0..1`: 0 day, 1 black night.
  double get darkness;

  /// The colour of the dark.
  Color get ambient;

  /// How thick the air is with rain and mist, `0..1`: it haloes every light.
  double get haze;

  /// How much colour the lights add over what they reveal, `0..1`.
  double get glow;
}

/// How much light reaches a point, and in what colour: what [LightField]
/// writes into one reused instance, so asking costs no allocation.
class LightSample {
  /// The light reaching it, `0..` (1 lifts the night fully; the base share
  /// left of the night included).
  double light = 0;

  /// What the lights give it beyond the base, `0..`.
  double added = 0;

  /// Light thrown on toward the eye by a drop there (forward scatter).
  double scattered = 0;

  /// The lights' mean colour there, `0..1` each.
  double red = 1;
  double green = 1;
  double blue = 1;

  /// The colour as a [Color].
  Color get color => Color.from(alpha: 1, red: red, green: green, blue: blue);
}

/// Every light of a scene in one frame, as flat data, and how much of it
/// reaches a point.
///
/// Built once a frame by the stage, read by everything that is lit: rain,
/// wet walls, water, the lighting that draws the night, shaders (through
/// [writeLight]). Nothing walks the component tree to find a light.
class LightField {
  /// Floats per light in [data]; see the `_` offsets.
  static const int stride = 22;

  static const int _x = 0;
  static const int _y = 1;
  static const int _ahead = 2;
  static const int _shape = 3;
  static const int _r = 4;
  static const int _g = 5;
  static const int _b = 6;
  static const int _strength = 7;
  static const int _radius = 8;
  static const int _dirX = 9;
  static const int _dirY = 10;
  static const int _cosFull = 11;
  static const int _cosEdge = 12;
  static const int _extentX = 13;
  static const int _extentY = 14;
  static const int _source = 15;
  static const int _stands = 16;
  static const int _falloff = 17;
  static const int _half = 18;
  static const int _edge = 19;
  static const int _spill = 20;
  static const int _spillRadius = 21;

  Float32List data = Float32List(stride * 16);

  /// Lights in [data].
  int count = 0;

  /// What stands in the lights' way; null: nothing.
  ShadowSet? shadows;

  /// The scene's darkness, `0..1`; 0 by day.
  double darkness = 0;

  /// The colour of the dark.
  Color ambient = const Color(0xFF060A16);

  /// The haze, `0..1`.
  double haze = 0;

  /// The colour lights add, `0..1`.
  double glow = 0;

  /// Whether anything needs lighting at all: dark, or some light on.
  bool get isLit => darkness > 0 || count > 0;

  /// Starts a frame's field over: no lights, [ambience]'s night (day when
  /// there is none).
  void begin(Ambience? ambience) {
    count = 0;
    darkness = ambience?.darkness.clamp(0.0, 1.0) ?? 0;
    ambient = ambience?.ambient ?? const Color(0xFF060A16);
    haze = ambience?.haze.clamp(0.0, 1.0) ?? 0;
    glow = ambience?.glow.clamp(0.0, 1.0) ?? 0;
  }

  /// Adds [light] at world [x], [y] (its anchor on its carrier), turned by
  /// [angle] with the carrier, as it is at [time]. Lights with no strength
  /// now are left out.
  void add(
    Light light,
    double x,
    double y,
    double angle,
    double time,
    StreetProjection? projection,
  ) {
    final strength = light.strengthAt(time, darkness);
    if (strength <= 0) {
      return;
    }
    if ((count + 1) * stride > data.length) {
      data = Float32List(data.length * 2)..setAll(0, data);
    }
    final o = count * stride;
    final direction = light.direction + angle;
    final half = light.spread / 2;
    final edge = half * light.softEdge.clamp(0.0, 1.0);
    data
      ..[o + _x] = x
      ..[o + _y] = y
      ..[o + _ahead] = projection?.ahead(light.depth) ?? 0
      ..[o + _shape] = light.shape.index.toDouble()
      ..[o + _r] = light.color.r
      ..[o + _g] = light.color.g
      ..[o + _b] = light.color.b
      ..[o + _strength] = strength
      ..[o + _radius] = light.radius
      ..[o + _dirX] = math.cos(direction)
      ..[o + _dirY] = math.sin(direction)
      ..[o + _cosFull] = math.cos(half - edge)
      ..[o + _cosEdge] = math.cos(half)
      ..[o + _extentX] = light.extent.x
      ..[o + _extentY] = light.extent.y
      ..[o + _source] = light.sourceRadius
      ..[o + _stands] =
          light.standsAt ?? projection?.yAt(light.depth) ?? double.nan
      ..[o + _falloff] = light.falloff.index.toDouble()
      ..[o + _half] = half
      ..[o + _edge] = edge
      ..[o + _spill] = light.shape == LightShape.cone ? light.spill : 0
      ..[o + _spillRadius] = light.spillRadius;
    count++;
  }

  // Per light, read back.
  double xOf(int i) => data[i * stride + _x];
  double yOf(int i) => data[i * stride + _y];
  double aheadOf(int i) => data[i * stride + _ahead];
  LightShape shapeOf(int i) =>
      LightShape.values[data[i * stride + _shape].round()];
  double strengthOf(int i) => data[i * stride + _strength];
  double radiusOf(int i) => data[i * stride + _radius];
  double directionOf(int i) =>
      math.atan2(data[i * stride + _dirY], data[i * stride + _dirX]);
  double halfSpreadOf(int i) => data[i * stride + _half];
  double edgeOf(int i) => data[i * stride + _edge];
  double extentXOf(int i) => data[i * stride + _extentX];
  double extentYOf(int i) => data[i * stride + _extentY];
  double sourceRadiusOf(int i) => data[i * stride + _source];
  /// World y of the ground light [i] stands on: as it says, or where its
  /// depth meets the street's ground; `null` with neither (no street).
  double? standsAtOf(int i) {
    final y = data[i * stride + _stands];
    return y.isNaN ? null : y;
  }
  Color colorOf(int i) => Color.from(
    alpha: 1,
    red: data[i * stride + _r],
    green: data[i * stride + _g],
    blue: data[i * stride + _b],
  );

  /// The share light [i] throws all round near its source, and how far.
  double spillOf(int i) => data[i * stride + _spill];
  double spillRadiusOf(int i) => data[i * stride + _spillRadius];

  /// How far light [i] reaches at all, world units.
  double reachOf(int i) => math.max(radiusOf(i), spillRadiusOf(i));

  /// Whether light [i] falls off physically rather than smoothly.
  bool isPhysicalOf(int i) => data[i * stride + _falloff] > 0.5;

  /// Writes light [i] for a shader as five vec4 at [at]: (x, y, ahead,
  /// shape), (r, g, b, strength), (radius, dirX, dirY, cosFull), (cosEdge,
  /// extentX, extentY, source), (spill, spill radius, 0, 0).
  void writeLight(int i, Float32List into, int at) {
    final o = i * stride;
    into
      ..[at] = data[o + _x]
      ..[at + 1] = data[o + _y]
      ..[at + 2] = data[o + _ahead]
      ..[at + 3] = data[o + _shape]
      ..[at + 4] = data[o + _r]
      ..[at + 5] = data[o + _g]
      ..[at + 6] = data[o + _b]
      ..[at + 7] = data[o + _strength]
      ..[at + 8] = data[o + _radius]
      ..[at + 9] = data[o + _dirX]
      ..[at + 10] = data[o + _dirY]
      ..[at + 11] = data[o + _cosFull]
      ..[at + 12] = data[o + _cosEdge]
      ..[at + 13] = data[o + _extentX]
      ..[at + 14] = data[o + _extentY]
      ..[at + 15] = data[o + _source]
      ..[at + 16] = data[o + _spill]
      ..[at + 17] = data[o + _spillRadius]
      ..[at + 18] = 0
      ..[at + 19] = 0;
  }

  /// Floats [writeLight] writes.
  static const int lightFloats = 20;

  /// Radius of the halo the haze makes round light [i]'s source.
  double haloRadiusOf(int i) => sourceRadiusOf(i) * (6 + 24 * haze);

  /// How much of light [i] reaches world [x], [y] at [inFront] world units in
  /// front of the street line (light and point at different depths are that
  /// much farther apart), `0..` times its strength. Also gives back, in
  /// [toward], the unit way from the light to the point, along x, y and the
  /// depth, for scattering.
  double reach(
    int i,
    double x,
    double y,
    double inFront, [
    Float32List? toward,
  ]) {
    final o = i * stride;
    final shape = data[o + _shape].round();
    final strength = data[o + _strength];
    if (shape == LightShape.directional.index) {
      toward
        ?..[0] = data[o + _dirX]
        ..[1] = data[o + _dirY]
        ..[2] = 0;
      return strength;
    }
    // The nearest point of what glows to the point.
    var lx = data[o + _x];
    var ly = data[o + _y];
    if (shape == LightShape.area.index) {
      final hw = data[o + _extentX] / 2;
      final hh = data[o + _extentY] / 2;
      lx = x.clamp(lx - hw, lx + hw);
      ly = y.clamp(ly - hh, ly + hh);
    } else if (shape == LightShape.line.index) {
      final ux = data[o + _dirX];
      final uy = data[o + _dirY];
      final half = data[o + _extentX] / 2;
      final along = ((x - lx) * ux + (y - ly) * uy).clamp(-half, half);
      lx += ux * along;
      ly += uy * along;
    }
    final dx = x - lx;
    final dy = y - ly;
    final dz = inFront - data[o + _ahead];
    final d2 = dx * dx + dy * dy + dz * dz;
    final radius = data[o + _radius];
    final spill = data[o + _spill];
    final spillRadius = spill > 0 ? data[o + _spillRadius] : 0.0;
    if (d2 >= radius * radius && d2 >= spillRadius * spillRadius) {
      return 0;
    }
    final d = math.sqrt(d2);
    if (toward != null) {
      if (d < 1e-6) {
        toward
          ..[0] = 0
          ..[1] = 0
          ..[2] = 1;
      } else {
        toward
          ..[0] = dx / d
          ..[1] = dy / d
          ..[2] = dz / d;
      }
    }
    var amount = 0.0;
    if (d < radius) {
      final t = 1 - d / radius;
      final fall = data[o + _falloff] < 0.5
          ? t * t
          : 1 / (1 + 16 * d2 / (radius * radius)) * math.min(1, t * 4);
      amount = strength * fall;
      if (shape == LightShape.cone.index) {
        amount *= _coneAt(o, dx, dy);
      }
    }
    if (d < spillRadius) {
      // What the source throws all round, near it.
      final t = 1 - d / spillRadius;
      amount = math.max(amount, strength * spill * t * t);
    }
    final shadows = this.shadows;
    if (amount > 0 && shadows != null && shadows.count > 0) {
      amount *= shadows.through(
        lx,
        ly,
        data[o + _ahead],
        x,
        y,
        inFront,
        math.max(data[o + _source], 1),
      );
    }
    return amount;
  }

  /// How much of a cone's light leaves along (dx, dy), `0..1`: full along
  /// its middle, easing out over its soft edge.
  double _coneAt(int o, double dx, double dy) {
    final flat = math.sqrt(dx * dx + dy * dy);
    if (flat < 1e-6) {
      return 1;
    }
    final c = (dx * data[o + _dirX] + dy * data[o + _dirY]) / flat;
    if (c >= data[o + _cosFull]) {
      return 1;
    }
    if (c <= data[o + _cosEdge]) {
      return 0;
    }
    final off = math.acos(c.clamp(-1.0, 1.0));
    final half = data[o + _half];
    final edge = data[o + _edge];
    final s = ((half - off) / math.max(edge, 1e-6)).clamp(0.0, 1.0);
    return s * s * (3 - 2 * s);
  }

  final Float32List _toward = Float32List(3);

  /// How lit world [x], [y] is, [inFront] of the street line, into [out]:
  /// the base left of the night plus every light reaching it, and their mean
  /// colour; with [forwardScatter] above 0 also what a drop of water there
  /// throws on toward the eye (Henyey-Greenstein, g [forwardScatter]): a
  /// drop between the eye and a lamp flares, one beside it shows what
  /// reaches it, one behind the lamp less.
  void sample(
    double x,
    double y,
    LightSample out, {
    double inFront = 0,
    double forwardScatter = 0,
  }) {
    final base = 1 - darkness;
    final g = forwardScatter;
    var total = 0.0;
    var scattered = base;
    var r = 0.0;
    var gr = 0.0;
    var b = 0.0;
    for (var i = 0; i < count; i++) {
      final amount = reach(i, x, y, inFront, g > 0 ? _toward : null);
      if (amount <= 0) {
        continue;
      }
      if (g > 0) {
        // The light goes from the lamp to the drop; the eye looks back
        // along the depth: the cosine between the two ways.
        final mu = _toward[2];
        // Henyey-Greenstein, x^1.5 as x * sqrt(x).
        final q = (1 + g * g) / (1 + g * g - 2 * g * mu);
        final phase = q * math.sqrt(q);
        scattered += amount * phase;
      }
      final o = i * stride;
      total += amount;
      r += data[o + _r] * amount;
      gr += data[o + _g] * amount;
      b += data[o + _b] * amount;
    }
    out
      ..added = total
      ..light = base + total
      ..scattered = g > 0 ? scattered : base + total;
    if (total <= 0) {
      out
        ..red = 1
        ..green = 1
        ..blue = 1;
    } else {
      out
        ..red = r / total
        ..green = gr / total
        ..blue = b / total;
    }
  }
}
