import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroundLift', () {
    test('level ground lifts nothing anywhere', () {
      final lift = GroundLift.sampled(0, 10, 11, (_) => 0);
      expect(lift.isLevel, isTrue);
      expect(lift.at(-5), 0);
      expect(lift.at(5.5), 0);
    });

    test('a hill is followed between samples and held past the ends', () {
      final lift = GroundLift.sampled(0, 10, 11, (x) => x * 0.2);
      expect(lift.isLevel, isFalse);
      expect(lift.at(5.5), closeTo(1.1, 1e-12));
      expect(lift.at(-3), 0);
      expect(lift.at(30), closeTo(2, 1e-12));
      final (low, high) = lift.rangeIn(2, 4);
      expect(low, closeTo(0.4, 1e-12));
      expect(high, closeTo(0.8, 1e-12));
    });
  });

  test('on a hill the street line and the ground in front rise together', () {
    const band = Rect.fromLTWH(-10, 0, 20, 2);
    final level = StreetProjection(band);
    final hill = StreetProjection(
      band,
      lift: GroundLift.sampled(-10, 10, 21, (x) => x > 0 ? 1.5 : 0),
    );
    expect(hill.lineAt(5), closeTo(level.line - 1.5, 1e-9));
    expect(hill.groundYAt(5, 0.5), closeTo(level.yAt(0.5) - 1.5, 1e-9));
    expect(hill.groundYAt(-5, 0.5), closeTo(level.yAt(0.5), 1e-9));
    expect(hill.depthAtPoint(5, hill.groundYAt(5, 0.3)), closeTo(0.3, 1e-9));
    expect(hill, isNot(level));
  });
}
