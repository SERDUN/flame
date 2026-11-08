import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down to 520: the drops land on it.
class _Ground extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 120);
}

/// How many drops the rain holds in the air after [seconds] of rain of
/// [rainMmPerHour] mm an hour.
Future<int> _dropsInAir(
  FlameGame game,
  double rainMmPerHour, {
  double seconds = 3,
}) async {
  final rain = Rain(rainMmPerHour: rainMmPerHour, density: 100);
  game.world.addAll([_Ground(), rain]);
  await game.ready();
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.update(1 / 60);
  }
  return rain.dropsInAir;
}

void main() {
  testWithFlameGame('the drops a rain holds are as many as its rate says', (
    game,
  ) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final tuned = await _dropsInAir(game, 6);
    final twice = await _dropsInAir(game, 12);
    final heavy = await _dropsInAir(game, 60);

    // The rate's share of the tuned rain is how much denser the rain is.
    expect(twice, greaterThan(1.7 * tuned), reason: 'twice the rate');
    expect(heavy, greaterThan(8 * tuned), reason: 'ten times the rate');
  });

  testWithFlameGame('the rate is the one number the rain is read at', (
    game,
  ) async {
    final rain = Rain();
    expect(rain.rainMmPerHour, 6);
    expect(rain.rainIntensity, 1);

    // The rate sets the intensity, and the intensity sets the rate back: a
    // game that says "a downpour" and a game that says "12 mm an hour" mean
    // the same rain.
    rain.intensity = 2;
    expect(rain.rainMmPerHour, 12);
    expect(rain.rainIntensity, 2);
    rain.rainMmPerHour = 60;
    expect(rain.intensity, 10);
    expect(rain.rainIntensity, 10);
  });

  testWithFlameGame('the drops of a harder rain are the bigger ones', (
    game,
  ) async {
    // The sizes follow the rate (Marshall and Palmer), so a rain of 60 mm an
    // hour has the bigger drops its rate gives it.
    final light = Rain(rainMmPerHour: 6);
    final heavy = Rain(rainMmPerHour: 60);
    expect(heavy.rainIntensity, greaterThan(light.rainIntensity));
    expect(
      RainDrops.diameterMm(0.5, heavy.rainMmPerHour),
      greaterThan(RainDrops.diameterMm(0.5, light.rainMmPerHour)),
    );
  });
}
