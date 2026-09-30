import 'dart:math' as math;

import 'package:flame/components.dart';
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
