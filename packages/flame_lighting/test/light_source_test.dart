import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a light fades to nothing at its radius', () {
    final light = LightSource(position: Vector2.zero(), radius: 100);
    expect(light.lightAt(Vector2(1, 0)), closeTo(1, 0.05));
    expect(light.lightAt(Vector2(50, 0)), closeTo(0.25, 1e-9));
    expect(light.lightAt(Vector2(100, 0)), 0);
    expect(light.lightAt(Vector2(0, 150)), 0);
  });

  test('a cone shines along its axis and not behind it', () {
    final lamp = LightSource(
      position: Vector2.zero(),
      radius: 100,
      coneAngle: math.pi / 2,
    );
    expect(lamp.lightAt(Vector2(0, 40)), greaterThan(0.3), reason: 'below');
    expect(lamp.lightAt(Vector2(0, -40)), 0, reason: 'above');
    expect(lamp.lightAt(Vector2(40, 0)), 0, reason: 'to the side');
  });

  test('a flickering light dims now and then, never brightens', () {
    final light = LightSource(flicker: 0.5);
    final seen = <double>[];
    for (var i = 0; i < 100; i++) {
      light.update(0.05);
      seen.add(light.strength);
    }
    expect(seen.every((s) => s <= 1 && s >= 0.5), isTrue);
    expect(seen.reduce(math.min), lessThan(0.9));
  });
}
