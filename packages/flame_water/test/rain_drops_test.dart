import 'dart:math';

import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mean size of the drops of a rain of [rainMmPerHour] mm an hour, mm.
double _mean(double rainMmPerHour) {
  const n = 2000;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += RainDrops.diameterMm((i + 0.5) / n, rainMmPerHour);
  }
  return sum / n;
}

void main() {
  test(
    'drops stay between the smallest drawn and the largest that holds together',
    () {
      for (final rate in [0.1, 6.0, 100.0]) {
        for (final u in [0.0, 0.5, 0.999999]) {
          expect(
            RainDrops.diameterMm(u, rate),
            inInclusiveRange(RainDrops.minMm, RainDrops.maxMm),
          );
        }
      }
    },
  );

  test('harder rain has bigger drops', () {
    expect(_mean(0.6), lessThan(_mean(6)));
    expect(_mean(6), lessThan(_mean(60)));
  });

  test('the sizes follow the rain rate, not a game intensity', () {
    // A storm cell over the walker is a rate, not an intensity: the drops of
    // a rain of 60 mm an hour are the drops of that rate's rain, and they
    // are the drops the rate gives (Marshall and Palmer's law, with
    // lambda = 4.1 R^-0.21 per mm).
    final lambda = 4.1 * pow(60, -0.21);
    // The mean of the sizes the law gives between the smallest drawn and the
    // largest that holds together.
    var sum = 0.0;
    const n = 2000;
    for (var i = 0; i < n; i++) {
      final u = (i + 0.5) / n;
      final d =
          RainDrops.minMm -
          log(
                1 -
                    u *
                        (1 -
                            exp(-lambda * (RainDrops.maxMm - RainDrops.minMm))),
              ) /
              lambda;
      sum += d.clamp(RainDrops.minMm, RainDrops.maxMm);
    }
    expect(_mean(60), closeTo(sum / n, 0.05));
  });

  test(
    'fall speeds match the measured ones: 1 mm about 4 m/s, 2 mm about 6.5, 5 mm about 9',
    () {
      expect(RainDrops.terminalSpeed(1), closeTo(4.0, 0.3));
      expect(RainDrops.terminalSpeed(2), closeTo(6.5, 0.3));
      expect(RainDrops.terminalSpeed(5), closeTo(9.1, 0.3));
    },
  );

  test('a small drop takes up the wind sooner than a large one', () {
    final small = RainDrops.follow(
      0.1,
      RainDrops.responseSec(RainDrops.terminalSpeed(0.6)),
    );
    final large = RainDrops.follow(
      0.1,
      RainDrops.responseSec(RainDrops.terminalSpeed(4)),
    );
    expect(small, greaterThan(2 * large));
  });

  test('a streak is the path over one exposure', () {
    expect(RainDrops.streakLength(6), closeTo(0.3, 1e-9));
  });
}
