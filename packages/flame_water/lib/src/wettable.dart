import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_water/src/rain.dart';

/// Something rain wets: a wall, a road, a car.
///
/// Under the world's [Rain] its [wetness] rises the harder it rains, and
/// when the rain stops (or where it is [sheltered]) it dries - slowly, as
/// wet things do. What looks wet follows [wetness]: a wall's gloss, a road's
/// film of water.
mixin Wettable on Component {
  /// How wet it is now, `0..1`.
  double wetness = 0;

  /// How fast it gets wet in a steady rain (intensity 1): the share of the
  /// way to soaked it goes in a second.
  double get wetRate => 0.3;

  /// How fast it dries: the share of its wetness it loses in a second.
  double get dryRate => 0.02;

  /// Whether it is out of the rain: under an awning, indoors.
  bool get sheltered => false;

  @override
  void update(double dt) {
    super.update(dt);
    final rain = sheltered ? 0.0 : (Rain.of(this)?.intensity ?? 0);
    if (rain > 0) {
      wetness += (1 - wetness) * (1 - math.exp(-dt * wetRate * rain));
    } else {
      wetness -= wetness * (1 - math.exp(-dt * dryRate));
    }
  }
}
