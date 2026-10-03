import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/src/shadow.dart';
import 'package:flame_stage/src/stage.dart';
import 'package:flame_stage/src/street_projection.dart';
import 'package:flame_stage/src/weather.dart';

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
  /// It is added to the sky's light, not kept as a light of the field.
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
    this.switchOnBelow,
    this.standsAt,
    this.spill = 0,
    this.spillRadius = 0,
    this.sunToward,
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
    double? switchOnBelow,
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
         switchOnBelow: switchOnBelow,
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
    double? switchOnBelow,
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
         switchOnBelow: switchOnBelow,
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
    double? switchOnBelow,
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
         switchOnBelow: switchOnBelow,
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
    double? switchOnBelow,
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
         switchOnBelow: switchOnBelow,
       );

  /// Light from no place in view, the same everywhere: the moon, a glowing
  /// overcast sky. It adds to the sky's light (see [Ambience]).
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

  /// The sun: direct light from far off along [toward] - where its light
  /// goes, x across, y down, z out of the scene toward the eye - and
  /// everything in its way casts a shadow, sharp near what casts it and
  /// softer farther off (the sun is half a degree across). A sun low behind
  /// the eye lights the house fronts and lays long shadows into the scene; a
  /// sun behind the houses leaves their fronts to the sky.
  Light.sun({
    required Vector3 toward,
    Color color = const Color(0xFFFFF4E0),
    double intensity = 1,
  }) : this(
         shape: LightShape.directional,
         color: color,
         intensity: intensity,
         sourceRadius: 0,
         sunToward: toward,
       );

  LightShape shape;

  /// Where a sun's light goes ([Light.sun]); `null` for light from no
  /// place - the moon, an overcast sky - which only adds to the sky's.
  Vector3? sunToward;

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

  /// If set, a light sensor switches it: fully on while the sky's light
  /// ([LightField.skyLevel]) is at or below this, off once it is twice
  /// this, easing between - street lamps that light themselves at dusk.
  double? switchOnBelow;

  /// World y of the ground it stands on, if water should mirror it about
  /// there rather than about its depth's ground line.
  double? standsAt;

  /// How bright it is now, at [time] seconds under a sky giving [skyLevel].
  double strengthAt(double time, double skyLevel) {
    var s = intensity * dimmer;
    final below = switchOnBelow;
    if (below != null) {
      final t = below <= 0
          ? (skyLevel <= 0 ? 1.0 : 0.0)
          : (2 - skyLevel / below).clamp(0.0, 1.0);
      s *= t * t * (3 - 2 * t);
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

/// The light a scene is under before any lamp: the sky's, and the air
/// it comes through. One a scene (the lighting); none means the scene is
/// drawn as it is, unlit.
///
/// There is no night and no day: the sky gives some light, of some colour -
/// a great deal of white at noon, less and warm at dusk, a little blue from
/// the moon at night - and lamps add theirs. The eye adapts to the sky
/// ([LightField.exposure]): by day a lamp is a speck against it, at night
/// it is most of what there is.
mixin Ambience on OnStage {
  /// The colour of the sky's light.
  Color get sky;

  /// How much light the sky gives, in the units lights' intensities are
  /// in: 1 as much as a street lamp gives at its heart; noon is tens of
  /// times that, a moonlit night a few hundredths.
  double get skyLight;

  /// The dimmest sky the eye adapts to: under less, the scene is darker
  /// than the sky's own colour. 1 (a lamp's worth) by default.
  double get adaptation => 1;

  /// How long the eye takes to adapt to brighter light, seconds. 0: at once.
  double get adaptsIn => 0;

  /// How long it takes to adapt to dimmer light, seconds: far longer - the
  /// cones gain back most of their sensitivity over a minute or two, the
  /// rods over many. Four times [adaptsIn] by default.
  double get darkAdaptsIn => 4 * adaptsIn;

  /// How thick the air is with rain and mist, `0..1`: it haloes every
  /// light; `null`: as thick as the stage's weather makes it.
  double? get haze;

  /// How much colour the lights add in the air over what they light,
  /// `0..1`; `null`: as much as the air between the eye and the street
  /// scatters - 1 - exp(-3.912 d / V) over the eye's distance to the street
  /// d and the weather's visibility V (Koschmieder): next to none in clear
  /// air, a few hundredths in rain, more in a downpour.
  double? get glow;

  /// World units a metre: how [glow] puts the street's distance against the
  /// weather's visibility, in metres. 1 for a world in metres.
  double get metre => 1;
}

/// How much light reaches a point, and in what colour: what [LightField]
/// writes into one reused instance, so asking costs no allocation.
class LightSample {
  /// The light reaching it, `0..` (1 lifts the night fully; the base share
  /// left of the night included).
  double light = 0;

  /// What the lights give it beyond the base, `0..`.
  double added = 0;

  /// What the lighting makes of [light] on the screen, `0..1`: the base,
  /// and the lights filling what it leaves up to white ([LightField.fill]).
  double shown = 0;

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
  /// How bright the lighting shows a point lit by the sky to [base] (as the
  /// eye takes it, `0..1`) and by lamps to [lamps] more: the lamps fill what
  /// the base leaves up to white as film and the eye do - in proportion
  /// while faint, more and more slowly near white, never at a hard stop.
  /// The one curve: the compose shader (light_compose.frag) draws it, rain
  /// and anything else lit under the lighting reads it here.
  static double fill(double base, double lamps) {
    final room = math.max(1 - base.clamp(0.0, 1.0), 1e-4);
    return 1 - room * math.exp(-math.max(lamps, 0) / room);
  }

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

  /// The sky's light, each channel in lights' units: the ambience's sky
  /// and every directional light (the moon) added to it.
  double skyRed = 1;
  double skyGreen = 1;
  double skyBlue = 1;

  /// How bright the sky's light is (its luminance), in lights' units.
  double get skyLevel => 0.2126 * skyRed + 0.7152 * skyGreen + 0.0722 * skyBlue;

  /// What the eye's adaptation makes of light: everything seen is light
  /// times this. One over the sky's level, but no more than one over the
  /// ambience's adaptation: by day a lamp is a speck against the sky, at
  /// night the sky is dark and the lamps carry the scene. 1 with no
  /// ambience.
  double exposure = 1;

  /// The haze, `0..1`.
  double haze = 0;

  /// The colour lights add in the air, `0..1`.
  double glow = 0;

  /// Whether there is an ambience: a scene without one is drawn unlit.
  bool lit = false;

  /// Whether the lighting has anything to do: the sky, as seen, darker
  /// than white in some channel, or some light on.
  bool get isLit =>
      lit &&
      (count > 0 ||
          skyRed * exposure < 0.999 ||
          skyGreen * exposure < 0.999 ||
          skyBlue * exposure < 0.999);

  // The ambience's own sky level, which a lamp's sensor reads.
  double _sensed = 1;

  /// What a lamp's light sensor reads: the sky's level before the moon and
  /// the like are added ([Light.switchOnBelow]).
  double get sensorLevel => _sensed;

  /// Starts a frame's field over: no lights, [ambience]'s sky (white and
  /// unlit when there is none).
  void begin(
    Ambience? ambience, {
    WeatherState? weather,
    StreetProjection? projection,
    double viewX = 0,
  }) {
    if (ambience == null) {
      count = 0;
      _sunLevel = 0;
      lit = false;
      skyRed = skyGreen = skyBlue = 1;
      _sensed = 1;
      exposure = 1;
      haze = 0;
      glow = 0;
      return;
    }
    beginUnder(
      sky: ambience.sky,
      skyLight: ambience.skyLight,
      adaptation: ambience.adaptation,
      adaptsIn: ambience.adaptsIn,
      darkAdaptsIn: ambience.darkAdaptsIn,
      haze:
          ambience.haze ?? _hazeOf(weather, projection, viewX, ambience.metre),
      glow:
          ambience.glow ??
          airGlow(weather, projection, metre: ambience.metre, viewX: viewX),
    );
    airDepth = projection?.farDistance ?? 0;
    airVisibility = weather != null && weather.present
        ? weather.visibilityM * ambience.metre
        : double.infinity;
  }

  /// How deep the air the lamps light lies between the eye and the street
  /// line, world units; 0: no street, no air.
  double airDepth = 0;

  /// How far one sees through that air, world units (Koschmieder).
  double airVisibility = double.infinity;

  /// How much of the light in the air the air between the eye and the
  /// street scatters toward it (see [Ambience.glow]): none without a street
  /// or a weather.
  static double airGlow(
    WeatherState? weather,
    StreetProjection? projection, {
    double metre = 1,
    double viewX = 0,
  }) {
    if (weather == null || !weather.present || projection == null) {
      return 0;
    }
    final m = math.max(metre, 1e-6);
    final x = viewX / m;
    final eye = projection.eyeHeight / m;
    // Along the eye's way level to the street line, at the middle of the view.
    return 1 -
        weather.air.transmittance(
          (x: x, ahead: projection.farDistance / m, height: eye),
          (x: x, ahead: 0, height: eye),
        );
  }

  /// The haze round the lamps at the middle of the view, at a lamp's height
  /// on the street line ([WeatherState.hazeAt]).
  static double _hazeOf(
    WeatherState? weather,
    StreetProjection? projection,
    double viewX,
    double metre,
  ) {
    if (weather == null || !weather.present) {
      return 0;
    }
    final m = math.max(metre, 1e-6);
    final eye = (projection?.eyeHeight ?? 0) / m;
    return weather.hazeAt((x: viewX / m, ahead: 0, height: eye));
  }

  /// Starts a frame's field over under a sky of [sky] colour giving
  /// [skyLight] (see [Ambience]).
  void beginUnder({
    required Color sky,
    required double skyLight,
    double adaptation = 1,
    double adaptsIn = 0,
    double? darkAdaptsIn,
    double haze = 0,
    double glow = 0,
  }) {
    _adaptsIn = math.max(adaptsIn, 0);
    _darkAdaptsIn = math.max(darkAdaptsIn ?? 4 * adaptsIn, 0);
    count = 0;
    _sunLevel = 0;
    lit = true;
    final light = math.max(skyLight, 0.0);
    skyRed = sky.r * light;
    skyGreen = sky.g * light;
    skyBlue = sky.b * light;
    _sensed = skyLevel;
    _adaptation = math.max(adaptation, 1e-6);
    this.haze = haze.clamp(0.0, 1.0);
    this.glow = glow.clamp(0.0, 1.0);
  }

  double _adaptation = 1;
  double _adaptsIn = 0;
  double _darkAdaptsIn = 0;
  bool _adapted = false;

  /// Ends a frame's field: what the eye adapts to, now that every light is
  /// in, after [dt] seconds of adapting - quickly to brighter light
  /// ([Ambience.adaptsIn]), slowly to dimmer ([Ambience.darkAdaptsIn]: the
  /// eye's cones and rods). The first frame sees as adapted.
  ///
  /// The eye adapts to all it sees in [view] ([seenLevel]), the street
  /// before it laid out by [projection]; with no view, to the sky and the
  /// suns on open ground.
  void finish([double dt = 0, Rect? view, StreetProjection? projection]) {
    if (!lit) {
      _adapted = false;
      return;
    }
    final target = 1 / math.max(seenLevel(view, projection), _adaptation);
    if (!_adapted || _adaptsIn <= 0 || dt <= 0) {
      exposure = target;
      _adapted = true;
      return;
    }
    // In steps of brightness, not of the number.
    final brighter = target < exposure;
    final tau = brighter ? _adaptsIn : math.max(_darkAdaptsIn, 1e-6);
    final k = 1 - math.exp(-dt / tau);
    exposure = math.exp(
      math.log(exposure) + (math.log(target) - math.log(exposure)) * k,
    );
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
    final strength = light.strengthAt(time, _sensed);
    if (strength <= 0) {
      return;
    }
    final toward = light.sunToward;
    if (light.shape == LightShape.directional && toward == null) {
      // From no place: it is part of the sky's light.
      skyRed += light.color.r * strength;
      skyGreen += light.color.g * strength;
      skyBlue += light.color.b * strength;
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
          light.standsAt ?? projection?.groundYAt(x, light.depth) ?? double.nan
      ..[o + _falloff] = light.falloff.index.toDouble()
      ..[o + _half] = half
      ..[o + _edge] = edge
      ..[o + _spill] = light.shape == LightShape.cone ? light.spill : 0
      ..[o + _spillRadius] = light.spillRadius;
    if (toward != null) {
      // A sun: where its light goes, x and y where a light's way is kept,
      // z where its depth is; it reaches everywhere; it is half a degree
      // across, as wide as that at [sunDistance].
      final way = toward.normalized();
      data
        ..[o + _dirX] = way.x
        ..[o + _dirY] = way.y
        ..[o + _ahead] = way.z
        ..[o + _radius] = double.infinity
        ..[o + _source] = sunDistance * 0.0046;
      _sunLevel +=
          strength *
          (0.2126 * light.color.r +
              0.7152 * light.color.g +
              0.0722 * light.color.b) *
          math.max(way.y, 0);
    }
    count++;
  }

  /// How bright what is in [view] is, as the eye takes it in: the light
  /// falling over a grid across it, the sky's and every light's, on the
  /// house fronts above the street line and on the ground below it
  /// ([projection]), and of that the brightest a tenth of the view gets.
  /// That is what the eye sees as white (the anchoring of lightness: the
  /// brightest thing in view looks white, if it is big enough to count). A
  /// lit street at night is seen in its lamps' light; a far bulb is a speck
  /// and leaves the night dark. The sky's and the suns' level on open
  /// ground with no view or no light.
  double seenLevel(Rect? view, [StreetProjection? projection]) {
    if (view == null || view.isEmpty || count == 0) {
      return skyLevel + _sunLevel;
    }
    const across = 8;
    const down = 6;
    final levels = _levels;
    var n = 0;
    for (var j = 0; j < down; j++) {
      final y = view.top + view.height * (j + 0.5) / down;
      for (var i = 0; i < across; i++) {
        final x = view.left + view.width * (i + 0.5) / across;
        final inFront = projection != null && y > projection.lineAt(x)
            ? projection.ahead(projection.depthAtPoint(x, y))
            : 0.0;
        var level = skyLevel;
        for (var l = 0; l < count; l++) {
          final amount = reach(l, x, y, inFront);
          if (amount > 0) {
            level += amount * _luminanceOf(l);
          }
        }
        // And the lamps' light in the air before it, as the lighting lays
        // it over the view: in a downpour at night the brightest of what
        // the eye sees, and what it adapts to.
        if (glow > 0) {
          level += glow * airLightAt(x, y);
        }
        levels[n++] = level;
      }
    }
    levels.sort();
    return levels[(levels.length * 0.9).floor()];
  }

  final Float64List _levels = Float64List(48);

  double _luminanceOf(int i) {
    final o = i * stride;
    return 0.2126 * data[o + _r] +
        0.7152 * data[o + _g] +
        0.0722 * data[o + _b];
  }

  /// The lamps' light in the air over world [x], [y], before [glow]: each
  /// light's share of the air between the eye and the street line, lit as
  /// at the light ([airDepth], [airVisibility]), times its strength and
  /// luminance - what the lighting's air pass lays there (`light.frag`,
  /// `light_buffer.frag`: glowLength, airShare), without the shadows,
  /// which next to nothing casts in the air.
  double airLightAt(double x, double y) {
    if (airDepth <= 0) {
      return 0;
    }
    var total = 0.0;
    for (var i = 0; i < count; i++) {
      final o = i * stride;
      final shape = data[o + _shape].round();
      if (shape == LightShape.directional.index) {
        continue;
      }
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
      final dz = data[o + _ahead];
      final d = math.sqrt(dx * dx + dy * dy + dz * dz);
      final radius = data[o + _radius];
      final cone = shape == LightShape.cone.index ? _coneAt(o, dx, dy) : 1.0;
      var lit =
          cone * glowLength(d, radius, physical: data[o + _falloff] > 0.5);
      final spill = data[o + _spill];
      if (spill > 0) {
        lit = math.max(lit, spill * glowLength(d, data[o + _spillRadius]));
      }
      if (lit <= 0) {
        continue;
      }
      total += data[o + _strength] * _luminanceOf(i) * airShare(lit);
    }
    return total;
  }

  /// How long a stretch of air, lit as at the light itself, the eye's way
  /// passing [b] from a light of [radius] gathers: its falloff summed along
  /// the way - smooth, (1 - r/R)^2, or [physical], 1/(1 + 16 r^2/R^2). As
  /// the shaders' glowLength.
  static double glowLength(double b, double radius, {bool physical = false}) {
    if (b >= radius) {
      return 0;
    }
    final s = math.sqrt(radius * radius - b * b);
    if (physical) {
      final k = 16 / (radius * radius);
      final q = math.sqrt(1 + k * b * b);
      return 2 / (math.sqrt(k) * q) * math.atan(math.sqrt(k) * s / q);
    }
    final near = math.max(b, 1e-4 * radius);
    return (2 * b * b * s + 2 / 3 * s * s * s) / (radius * radius) -
        2 * b * b / radius * math.log((s + radius) / near);
  }

  /// How much of the glow a stretch [lit] long of air lit as at a light
  /// makes against what the whole air between the eye and the street line
  /// would: in clear air as much as its length, in a fog no more than the
  /// air one sees through. As the shaders' airShare.
  double airShare(double lit) {
    final v = math.max(airVisibility, 1e-3);
    final l = math.min(lit, airDepth);
    final whole = 1 - math.exp(-3.912 * airDepth / v);
    if (whole < 1e-6) {
      return l / airDepth;
    }
    return (1 - math.exp(-3.912 * l / v)) / whole;
  }

  /// How far off a sun's light is taken to come from, world units: far
  /// enough that its rays are parallel over a scene.
  static const double sunDistance = 1e5;

  /// Whether light [i] is a sun ([Light.sun]).
  bool isSunOf(int i) =>
      data[i * stride + _shape].round() == LightShape.directional.index;

  // The suns' light on open ground, for the eye's adaptation.
  double _sunLevel = 0;

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
  /// extentX, extentY, source), (spill, spill radius, physical, 0) -
  /// physical 1 for [Falloff.physical].
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
      ..[at + 18] = data[o + _falloff]
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
      return strength * _sunThrough(o, x, y, inFront, toward);
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
        data[o + _source],
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

  /// How much of sun [o]'s light gets to ([x], [y], [inFront]) past
  /// everything in its way.
  double _sunThrough(
    int o,
    double x,
    double y,
    double inFront,
    Float32List? toward,
  ) {
    final dx = data[o + _dirX];
    final dy = data[o + _dirY];
    final dz = data[o + _ahead];
    toward
      ?..[0] = dx
      ..[1] = dy
      ..[2] = dz;
    final shadows = this.shadows;
    if (shadows == null || shadows.count == 0) {
      return 1;
    }
    return shadows.through(
      x - dx * sunDistance,
      y - dy * sunDistance,
      inFront - dz * sunDistance,
      x,
      y,
      inFront,
      data[o + _source],
    );
  }

  /// How lit world [x], [y] is, [inFront] of the street line, into [out],
  /// as the eye sees it ([exposure]): the sky's light plus every light
  /// reaching it, and the lights' mean colour; with [forwardScatter] above
  /// 0 also what a drop of water there throws on toward the eye
  /// (Henyey-Greenstein, g [forwardScatter]): a drop between the eye and a
  /// lamp flares, one beside it shows what reaches it, one behind the lamp
  /// less.
  void sample(
    double x,
    double y,
    LightSample out, {
    double inFront = 0,
    double forwardScatter = 0,
  }) {
    final e = exposure;
    final base = lit ? math.min(skyLevel * e, 1.0) : 1.0;
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
        scattered += amount * e * phase;
      }
      final o = i * stride;
      total += amount;
      r += data[o + _r] * amount;
      gr += data[o + _g] * amount;
      b += data[o + _b] * amount;
    }
    out
      ..added = total * e
      ..light = base + total * e
      ..shown = fill(base, total * e)
      ..scattered = g > 0 ? scattered : base + total * e;
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
