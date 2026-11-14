import 'dart:math' as math;

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const eye = (x: 0.0, ahead: 40.0, height: 1.7);
  AirPoint at(double ahead, [double height = 1.7, double x = 0]) =>
      (x: x, ahead: ahead, height: height);

  test('uniform air: Koschmieder, a visibility of V leaves 2 % at V', () {
    final air = AirField(base: AirField.ofVisibility(100));
    expect(air.transmittance(eye, at(-60)), closeTo(0.02, 0.001));
    expect(air.visibilityAt(eye), closeTo(100, 1e-6));
  });

  test('a ground fog: the feet are in it, the tree tops above it', () {
    final air = AirField(
      banks: [
        AirBank(
          extinction: AirField.ofVisibility(30),
          topM: 1.2,
          topWidthM: 0.4,
        ),
      ],
    );
    final feet = air.extinctionAt(at(0, 0));
    final head = air.extinctionAt(at(0));
    final top = air.extinctionAt(at(0, 10));
    expect(feet, greaterThan(head * 20), reason: 'the head above its top');
    expect(top - air.base, lessThan(feet / 1000), reason: 'past it, clear air');
    // The sun through a metre-thick fog: hardly dimmed.
    expect(air.verticalOpticalDepth(0, 0), closeTo(3.912 / 30 * 1.2, 1e-3));
  });

  test(
    'a fog bank rolling in: clear on one side of its edge, thick past it',
    () {
      final air = AirField(
        banks: [
          AirBank(extinction: AirField.ofVisibility(20), at: 50, widthM: 10),
        ],
      );
      expect(air.visibilityAt(at(0, 1, 30)), greaterThan(10000));
      expect(air.visibilityAt(at(0, 1, 70)), lessThan(25));
      // Along the eye's way to a point past the edge the air thickens.
      final before = air.transmittance(
        (x: 30, ahead: 40, height: 1.7),
        (x: 30, ahead: 0, height: 1.7),
      );
      final past = air.transmittance(
        (x: 70, ahead: 40, height: 1.7),
        (x: 70, ahead: 0, height: 1.7),
      );
      expect(past, lessThan(before * 0.01));
    },
  );

  test('a bank lying away from the eye covers the far before the near', () {
    final air = AirField(
      banks: [
        AirBank(
          extinction: AirField.ofVisibility(20),
          at: 10,
          angle: -math.pi / 2,
          widthM: 4,
        ),
      ],
    );
    // Its edge 10 m behind the street line, toward the far trees.
    expect(air.extinctionAt(at(-30)), greaterThan(0.1));
    expect(air.extinctionAt(at(5)), lessThan(0.001));
  });
}
