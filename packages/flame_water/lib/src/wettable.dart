import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/src/rain.dart';

/// Something rain wets: a wall, a road, a car, a puddle.
///
/// Its [wetness] is the water it holds. Rain brings water on at [wetRate]
/// times how hard it rains, the more slowly the fuller it is; water leaves
/// it - runs off, soaks in, evaporates - at [dryRate] times the weather's
/// `Rain.drying`, the faster the more of it there is. So a steady rain
/// holds it where the two meet - a downpour near soaked, a drizzle less -
/// and when the rain stops it dries back to nothing: a wall first, the
/// asphalt next, a puddle last. Where it is [sheltered] no rain reaches
/// it. What looks wet follows [wetness]: a wall's gloss, a road's film of
/// water, how far a puddle spreads.
mixin Wettable on Component {
  /// How wet it is now, `0..1`: the water it holds against what it can.
  double wetness = 0;

  /// How fast rain wets it: in a steady rain (intensity 1), the share of
  /// the way to soaked it goes in a second.
  double wetRate = 0.3;

  /// How fast its water leaves it in the usual weather (`Rain.drying` 1):
  /// the share of its wetness it loses in a second. Its own - a wall drains
  /// fast, a puddle holds its water long.
  double dryRate = 0.02;

  /// How porous it is, `0..1`: 0 metal or glass, which water only lies on;
  /// about 0.4 asphalt, 0.6 brick or plaster, which soak it up.
  double porosity = 0.5;

  /// How much of its colour the water in it takes away now, `0..1`. Water
  /// filling the pores keeps light bouncing inside until much of it is
  /// absorbed, so a porous thing goes darker as it wets - soaked, down to
  /// a fifth of its colour at full porosity (Lagarde); metal not at all.
  /// It darkens first, while the pores fill.
  double get wetDarkening => 0.8 * porosity * _smooth(0, 0.5, wetness);

  /// How much it shines now, `0..1`: a film of water forms on it only once
  /// the pores are full, and goes first as it dries - a drying street is
  /// dull and dark before it pales.
  double get wetGloss => _smooth(0.4, 0.9, wetness);

  static double _smooth(double from, double to, double x) {
    final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Whether it is out of the rain: under an awning, indoors.
  bool get sheltered => false;

  @override
  void update(double dt) {
    super.update(dt);
    final weather = Rain.of(this);
    final wet = wetRate * (sheltered ? 0.0 : (weather?.intensity ?? 0));
    final dry = dryRate * (weather?.drying ?? 1);
    final rate = wet + dry;
    if (rate <= 0) {
      return;
    }
    // dw/dt = wet (1 - w) - dry w, solved over the step: it heads for the
    // wetness the two hold it at, and gets there by an exponential.
    final held = wet / rate;
    wetness = held + (wetness - held) * math.exp(-rate * dt);
  }
}

/// Something that shines and darkens as wet as it is: a wall, a roof, a
/// car. Ties a [Wettable]'s wetness to a [Glossy] look - it darkens as its
/// pores fill ([Wettable.wetDarkening]) and shines once a film forms on it
/// ([Wettable.wetGloss]), up to [soakedGloss].
mixin WetSheen on Glossy, Wettable {
  /// How glossy it is soaked, `0..1`: glazed tiles more than brick.
  double get soakedGloss => 0.6;

  @override
  double get gloss => soakedGloss * wetGloss;

  @override
  double get darkening => wetDarkening;
}
