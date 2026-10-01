import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';

/// Something rain wets: a wall, a road, a car, a puddle.
///
/// It holds water, mm ([waterMm]), as the stage's weather brings it and
/// takes it away, in the world's time (`Weather.pace`): the rain falling on
/// it ([rainShare] of it - an upright wall gets a little of what the wind
/// drives at it, a hollow collects from round it) comes in; what the air
/// takes (the weather's evaporation) and what soaks away into it
/// ([Substance.soaksMmPerHour]) goes out; past what it can hold
/// ([capacityMm]) the rest runs off. So a steady rain fills it, and when
/// the rain stops it dries as the air and its own make-up let it: a wall
/// in a warm wind at once, asphalt next, a deep puddle last - nobody tunes
/// a rate. What looks wet follows [wetness]: how dark its pores go, the
/// gloss of the film on it, how far a puddle spreads.
mixin Wettable on Component {
  /// What it is made of: how porous, how much it holds, how fast water
  /// soaks into it.
  Substance get substance => Substance.asphalt;

  /// How much of the rain falling on open ground reaches it: 0 out of the
  /// rain, 1 open ground, about 0.2 an upright wall, above 1 a hollow
  /// collecting the water round it.
  double get rainShare => sheltered ? 0 : 1;

  /// Whether it is out of the rain: under an awning, indoors.
  bool get sheltered => false;

  /// How much water it holds when full, mm: what its substance holds.
  double get capacityMm => substance.holdsMm;

  /// The water on and in it now, mm.
  double waterMm = 0;

  /// How wet it is, `0..1`: the water it holds against what it can.
  double get wetness {
    final capacity = capacityMm;
    return capacity <= 0 ? 0 : (waterMm / capacity).clamp(0.0, 1.0);
  }

  /// Makes it [value] wet now (`0..1` of what it holds).
  set wetness(double value) => waterMm = value.clamp(0.0, 1.0) * capacityMm;

  /// How much of its colour the water in it takes away now, `0..1`. Water
  /// filling the pores keeps light bouncing inside until much of it is
  /// absorbed, so a porous thing goes darker as it wets - soaked, down to
  /// a fifth of its colour at full porosity (Lagarde); metal not at all.
  /// It darkens first, while the pores fill.
  double get wetDarkening =>
      0.8 * substance.porosity * _smooth(0, 0.5, wetness);

  /// How much it shines now, `0..1`: a film of water forms on it only once
  /// the pores are full, and goes first as it dries - a drying street is
  /// dull and dark before it pales.
  double get wetGloss => _smooth(0.4, 0.9, wetness);

  static double _smooth(double from, double to, double x) {
    final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final weather = Stage.maybeOf(this)?.frame.weather;
    if (weather == null) {
      return;
    }
    soak(weather, dt);
  }

  /// Moves its water on by [dt] game seconds of [weather].
  void soak(WeatherState weather, double dt) {
    final hours = dt * weather.pace / 3600;
    if (hours <= 0) {
      return;
    }
    final gain = weather.rainMmPerHour * math.max(rainShare, 0);
    final loss = weather.evaporationMmPerHour + substance.soaksMmPerHour;
    waterMm = (waterMm + (gain - (waterMm > 0 ? loss : 0)) * hours).clamp(
      0.0,
      capacityMm,
    );
  }
}

/// Something that shines and darkens as wet as it is: a wall, a roof, a
/// car. Ties a [Wettable]'s wetness to a [Glossy] look - it darkens as its
/// pores fill ([Wettable.wetDarkening]) and shines once a film forms on it
/// ([Wettable.wetGloss]), as much as its substance is smooth
/// ([Substance.soakedGloss]).
mixin WetSheen on Glossy, Wettable {
  @override
  double get gloss => substance.soakedGloss * wetGloss;

  @override
  double get darkening => wetDarkening;
}
