import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('water mirrors 2 % straight down, from its refractive index', () {
    expect(WaterMedium.clear.f0, closeTo(0.0204, 1e-3));
    expect(WaterMedium.clear.fresnel(1), closeTo(WaterMedium.clear.f0, 1e-9));
    expect(WaterMedium.clear.fresnel(0), closeTo(1, 1e-9));
  });

  test('a puddle shows its bottom; a pond a metre deep does not', () {
    // Seen from 14 m with the eye 1.6 m up: the sine of the angle is 0.11.
    const s = 0.11;
    final puddle = WaterMedium.clear.transmission(0.02, s);
    expect(puddle.r, greaterThan(0.95));
    expect(puddle.b, greaterThan(0.99));
    final pond = WaterMedium.pond.transmission(1, s);
    expect(pond.r, lessThan(0.01));
    expect(pond.g, lessThan(0.01));
    expect(pond.b, lessThan(0.01));
  });

  test('deep clear water is blue, a pond green-brown, both dark', () {
    final clear = WaterMedium.clear.deepReflectance;
    expect(clear.b, greaterThan(clear.g));
    expect(clear.g, greaterThan(clear.r));
    final pond = WaterMedium.pond.deepReflectance;
    expect(pond.g, greaterThan(pond.r));
    expect(pond.g, greaterThan(pond.b));
    for (final v in [clear.r, clear.g, clear.b, pond.r, pond.g, pond.b]) {
      expect(v, lessThan(0.06), reason: 'water is dark: a few percent back');
    }
  });

  test('seen low, light goes down steeply: refraction bends it', () {
    // Even looking along the water the way under it is within 49 degrees
    // of straight down.
    expect(WaterMedium.clear.cosRefracted(0), greaterThan(0.65));
    expect(WaterMedium.clear.cosRefracted(1), closeTo(1, 1e-9));
  });
}
