import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

double _mean(double intensity) {
  const n = 2000;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += RainDrops.diameterMm((i + 0.5) / n, intensity);
  }
  return sum / n;
}

void main() {
  test(
    'drops stay between the smallest drawn and the largest that holds together',
    () {
      for (final intensity in [0.1, 1.0, 2.2]) {
        for (final u in [0.0, 0.5, 0.999999]) {
          expect(
            RainDrops.diameterMm(u, intensity),
            inInclusiveRange(RainDrops.minMm, RainDrops.maxMm),
          );
        }
      }
    },
  );

  test('harder rain has bigger drops', () {
    expect(_mean(0.3), lessThan(_mean(1)));
    expect(_mean(1), lessThan(_mean(2)));
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
