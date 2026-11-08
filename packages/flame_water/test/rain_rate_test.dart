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

/// The drops the rain holds in the air after [seconds] of rain of
/// [rainMmPerHour] mm an hour, by their diameters, mm.
Future<List<double>> _dropsInAir(
  FlameGame game,
  double rainMmPerHour, {
  double seconds = 6,
}) async {
  final rain = Rain(rainMmPerHour: rainMmPerHour, density: 100);
  game.world.addAll([_Ground(), rain]);
  await game.ready();
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.update(1 / 60);
  }
  final drops = [for (final d in rain.dropLooks) d.diameterMm];
  rain.removeFromParent();
  game.world.children.whereType<_Ground>().forEach((g) => g.removeFromParent());
  await game.ready();
  return drops;
}

/// The cross-section [drops] hold, mm^2.
double _area(List<double> drops) => drops.fold(0, (sum, d) => sum + d * d);

void main() {
  testWithFlameGame('the drops a rain holds hide as much as its haze', (
    game,
  ) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    // Each held once the rain has filled the air: settled against settled.
    final tuned = _area(await _dropsInAir(game, 6));
    for (final rate in [3.0, 12.0, 60.0]) {
      final drops = await _dropsInAir(game, rate);
      // The haze of the rain is its drops' cross-section in the air; the
      // drops drawn hold as much more of it as the haze of their rate
      // takes more of the light - neither the rate's share of the tuned rain
      // (ten times at 60 mm an hour, against a haze of 4.3) nor less.
      final share = WeatherState.rainHazeShare(rate);
      expect(
        _area(drops) / tuned,
        closeTo(share, 0.12 * share),
        reason: '$rate mm an hour: the haze takes $share times the tuned',
      );
    }
  });

  test(
    'a harder rain lets fewer drops fall than its rate says, bigger ones',
    () {
      // Ten times the tuned rain: the haze some 4.3 times, its drops bigger
      // and in the air the shorter for falling faster, so some 3.2 times as
      // many fall - and some 2.5 times as many are in the air - not ten.
      final share = RainDrops.releaseShare(
        60,
        tunedMmPerHour: WeatherState.tunedRainMmPerHour,
        hazeShare: WeatherState.rainHazeShare(60),
      );
      expect(share, inInclusiveRange(2.8, 3.6));
      expect(
        RainDrops.releaseShare(
          6,
          tunedMmPerHour: 6,
          hazeShare: WeatherState.rainHazeShare(6),
        ),
        closeTo(1, 1e-9),
      );
      expect(
        RainDrops.releaseShare(0, tunedMmPerHour: 6, hazeShare: 0),
        0,
      );
    },
  );

  test('the drops a rain lets fall are read off the law at any rate', () {
    for (final rate in [0.05, 0.6, 3.0, 6.0, 17.0, 60.0, 400.0, 2000.0]) {
      final law = RainDrops.releaseShare(
        rate,
        tunedMmPerHour: WeatherState.tunedRainMmPerHour,
        hazeShare: WeatherState.rainHazeShare(rate),
      );
      expect(Rain.dropShareOf(rate), closeTo(law, law * 1e-3), reason: '$rate');
    }
    expect(Rain.dropShareOf(0), 0);
    expect(Rain(rainMmPerHour: 60).dropShare, Rain.dropShareOf(60));
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
