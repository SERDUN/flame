import 'package:flutter/foundation.dart' show immutable;

/// What a surface is made of, as rain, light and a body meet it.
///
/// Everything that differs between asphalt and a tin roof is here, in
/// physical terms, rather than tuned per thing: how much water its pores take
/// and how much lies on it before it runs off, how fast what it holds soaks
/// in, how rough it is (how much it shines when wet, how broken its
/// reflection), how a drop bounces off it, whether a drop splashes on it, how
/// loud rain is on it and what a drop on it sounds like, and its friction for
/// a body standing on it. A thing
/// says what it is made of; the rain, the water and the lighting do the rest.
@immutable
class Substance {
  const Substance({
    required this.name,
    this.porosity = 0,
    this.holdsMm = 0.5,
    this.soaksMmPerHour = 0,
    this.roughness = 0.5,
    this.restitution = 0.2,
    this.slip = 0.8,
    this.splashAbove = 57.7,
    this.loudness = 0.5,
    this.soundHz = 2000,
    this.ringSec = 0.002,
    this.hitSec = 0.006,
    this.friction = 0.6,
  });

  /// Asphalt: a little porous, rough, a thin film of water before it runs.
  static const asphalt = Substance(
    name: 'asphalt',
    porosity: 0.4,
    holdsMm: 1,
    soaksMmPerHour: 0.5,
    roughness: 0.7,
    restitution: 0.1,
    slip: 0.6,
    loudness: 0.35,
    soundHz: 6000,
    ringSec: 0,
    hitSec: 0.002,
    friction: 0.8,
  );

  /// Brick and plaster: porous, they darken a great deal as they soak.
  static const brick = Substance(
    name: 'brick',
    porosity: 0.6,
    holdsMm: 2,
    soaksMmPerHour: 2,
    roughness: 0.8,
    restitution: 0.1,
    slip: 0.5,
    loudness: 0.3,
    soundHz: 5000,
    ringSec: 0,
    hitSec: 0.002,
    friction: 0.9,
  );

  /// Concrete: between asphalt and brick.
  static const concrete = Substance(
    name: 'concrete',
    porosity: 0.5,
    holdsMm: 1.5,
    soaksMmPerHour: 1,
    roughness: 0.7,
    restitution: 0.12,
    slip: 0.6,
    loudness: 0.35,
    soundHz: 6000,
    ringSec: 0,
    hitSec: 0.002,
    friction: 0.9,
  );

  /// Glass and glazed tiles: no pores, smooth, a clear mirror wet.
  static const glass = Substance(
    name: 'glass',
    holdsMm: 0.2,
    roughness: 0.05,
    restitution: 0.3,
    slip: 0.95,
    loudness: 0.6,
    soundHz: 4000,
    ringSec: 0.03,
    hitSec: 0.0015,
    friction: 0.4,
  );

  /// Sheet metal: a tin roof, a car: no pores, loud under rain.
  static const metal = Substance(
    name: 'metal',
    holdsMm: 0.2,
    roughness: 0.2,
    restitution: 0.4,
    slip: 0.9,
    loudness: 1,
    soundHz: 2600,
    ringSec: 0.12,
    hitSec: 0.0015,
    friction: 0.5,
  );

  /// Umbrella canvas: tight woven fabric that sheds water, taut and drumming.
  /// A drop on it is a crisp tap: the fabric is a membrane so damped and so
  /// dense in its modes that it rings at no note of its own.
  static const canvas = Substance(
    name: 'canvas',
    porosity: 0.05,
    holdsMm: 0.3,
    restitution: 0.35,
    slip: 0.85,
    loudness: 0.7,
    soundHz: 1800,
    ringSec: 0,
    friction: 0.7,
  );

  /// Clothes and skin: soak water up.
  static const cloth = Substance(
    name: 'cloth',
    porosity: 0.8,
    holdsMm: 3,
    soaksMmPerHour: 30,
    roughness: 0.9,
    restitution: 0.02,
    slip: 0.3,
    splashAbove: 120,
    loudness: 0.1,
    soundHz: 700,
    ringSec: 0,
    hitSec: 0.02,
    friction: 0.8,
  );

  /// Leaves and grass: shed water, soft under rain.
  static const foliage = Substance(
    name: 'foliage',
    porosity: 0.1,
    soaksMmPerHour: 5,
    roughness: 0.6,
    restitution: 0.15,
    slip: 0.7,
    splashAbove: 90,
    loudness: 0.2,
    soundHz: 3000,
    ringSec: 0,
    hitSec: 0.008,
    friction: 0.8,
  );

  /// Bare earth: a path, a flower bed. It drinks the rain and deadens it.
  static const soil = Substance(
    name: 'soil',
    porosity: 0.5,
    holdsMm: 3,
    soaksMmPerHour: 10,
    roughness: 0.85,
    restitution: 0.02,
    slip: 0.3,
    splashAbove: 110,
    loudness: 0.15,
    soundHz: 800,
    ringSec: 0,
    hitSec: 0.01,
  );

  /// Wood: a bench, a fence.
  static const wood = Substance(
    name: 'wood',
    porosity: 0.4,
    holdsMm: 1,
    soaksMmPerHour: 1,
    roughness: 0.6,
    restitution: 0.15,
    slip: 0.6,
    loudness: 0.45,
    soundHz: 1600,
    ringSec: 0.01,
    hitSec: 0.003,
    friction: 0.7,
  );

  /// Standing water: a puddle's surface. A drop sinks into it unless it hits
  /// hard enough to throw a crown up.
  static const water = Substance(
    name: 'water',
    holdsMm: double.infinity,
    roughness: 0,
    restitution: 0,
    slip: 1,
    splashAbove: 100,
    loudness: 0.4,
    soundHz: 2500,
    ringSec: 0.02,
    hitSec: 0.003,
    friction: 0.1,
  );

  /// What it is called, for logs and tools.
  final String name;

  /// How porous it is, `0..1`: 0 metal or glass, which water only lies on;
  /// about 0.4 asphalt, 0.6 brick, which soak it up and darken.
  final double porosity;

  /// How much water, mm, it holds before more runs off: what fills its
  /// pores and the film on it.
  final double holdsMm;

  /// How fast the water on it soaks away into it and below, mm per hour.
  final double soaksMmPerHour;

  /// How rough it is, `0..1`: 0 a mirror, 1 matte. Wet, it shines as much
  /// as it is smooth, and its reflection smears as much as it is rough.
  final double roughness;

  /// Share of a drop's speed into it the drop keeps, thrown back off it.
  final double restitution;

  /// Share of a drop's speed along it the drop keeps: the rest it drags.
  final double slip;

  /// The impact number (`Rain.impactNumber`) above which a drop splashes on
  /// it rather than spreading.
  final double splashAbove;

  /// How loud rain is on it, `0..1`: a tin roof 1, cloth near nothing.
  final double loudness;

  /// Where the sound of a drop striking it sits, Hz. A strike is a click of
  /// every frequency, and the surface takes off the highs above this: asphalt
  /// and stone clicks bright (some 6 kHz), cloth and earth thud low. A
  /// surface that rings rings about here: a tin roof, glass, a puddle's
  /// bubble (some 3 kHz for a millimetre one, Minnaert).
  final double soundHz;

  /// How long it rings on after a drop, seconds, to a third: sheet metal a
  /// tenth of a second, glass and a bubble in water a few hundredths, stone,
  /// cloth and earth not at all.
  final double ringSec;

  /// How long the strike itself lasts, seconds: a hard thing a few
  /// thousandths (a click), a soft one that gives under the drop longer (a
  /// pat).
  final double hitSec;

  /// Its friction for a body standing or sliding on it.
  final double friction;

  /// The same substance with some of its properties changed: canvas drawn
  /// tauter sounds higher.
  Substance copyWith({
    String? name,
    double? loudness,
    double? soundHz,
    double? ringSec,
    double? hitSec,
  }) => Substance(
    name: name ?? this.name,
    porosity: porosity,
    holdsMm: holdsMm,
    soaksMmPerHour: soaksMmPerHour,
    roughness: roughness,
    restitution: restitution,
    slip: slip,
    splashAbove: splashAbove,
    loudness: loudness ?? this.loudness,
    soundHz: soundHz ?? this.soundHz,
    ringSec: ringSec ?? this.ringSec,
    hitSec: hitSec ?? this.hitSec,
    friction: friction,
  );

  /// How glossy it is soaked, `0..1`: smooth things more.
  double get soakedGloss => 0.15 + 0.75 * (1 - roughness);

  @override
  String toString() => 'Substance($name)';
}
