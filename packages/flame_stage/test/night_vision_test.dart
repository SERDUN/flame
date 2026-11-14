import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

double _saturation(Color c) {
  final high = [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b);
  final low = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);
  return high == 0 ? 0 : (high - low) / high;
}

void main() {
  const vision = NightVision(fullBelow: 0.1, noneAbove: 5);
  const orange = Color(0xFFC87828);

  test('the shift is whole dark-adapted, none in daylight, smooth between', () {
    expect(vision.amountAt(0.01), 1);
    expect(vision.amountAt(0.1), 1);
    expect(vision.amountAt(5), 0);
    expect(vision.amountAt(500), 0);
    var last = 1.0;
    for (var level = 0.1; level <= 5; level *= 1.2) {
      final s = vision.amountAt(level);
      expect(s, lessThanOrEqualTo(last));
      last = s;
    }
    // Half way in the logarithm, half the shift.
    expect(vision.amountAt(0.7071067811865476), closeTo(0.5, 1e-9));
  });

  test('a colour fades and turns bluer with the shift; none leaves it', () {
    expect(vision.apply(orange, 0), orange);
    final night = vision.apply(orange, 1);
    expect(_saturation(night), lessThan(_saturation(orange) / 2));
    expect(night.b / night.r, greaterThan(orange.b / orange.r * 2));
    final dusk = vision.apply(orange, 0.5);
    expect(_saturation(dusk), lessThan(_saturation(orange)));
    expect(_saturation(dusk), greaterThan(_saturation(night)));
    // A grey stays grey in brightness, only cooler.
    const grey = Color(0xFF808080);
    final cool = vision.apply(grey, 1);
    expect(cool.b, greaterThan(cool.r));
  });

  test('the matrix is the same map as the colour', () {
    final m = vision.matrix(0.6);
    final c = vision.apply(orange, 0.6);
    double row(int i) =>
        m[i * 5] * orange.r + m[i * 5 + 1] * orange.g + m[i * 5 + 2] * orange.b;
    expect(row(0), closeTo(c.r, 1e-9));
    expect(row(1), closeTo(c.g, 1e-9));
    expect(row(2), closeTo(c.b, 1e-9));
    expect(m.sublist(15), [0, 0, 0, 1, 0], reason: 'alpha kept');
    expect([m[4], m[9], m[14]], [0, 0, 0], reason: 'nothing added');
  });

  test("the field's shift follows the eye's adaptation", () {
    final field = LightField();
    void under(double skyLight) => field.beginUnder(
      sky: const Color(0xFFFFFFFF),
      skyLight: skyLight,
      adaptation: 0.05,
      adaptsIn: 1,
      darkAdaptsIn: 40,
      nightVision: vision,
    );
    under(40);
    field.finish();
    expect(field.scotopic, 0, reason: 'daylight');
    // Night falls: the eye, still adapted to the day, sees no shift yet;
    // it comes as the eye adapts.
    under(0.05);
    field.finish(1);
    expect(field.scotopic, 0);
    for (var i = 0; i < 600; i++) {
      under(0.05);
      field.finish(1);
    }
    expect(field.scotopic, closeTo(1, 1e-6), reason: 'dark-adapted');
    field.beginUnder(sky: const Color(0xFFFFFFFF), skyLight: 0.05);
    field.finish(1);
    expect(field.scotopic, 0, reason: 'no night vision');
  });
}
