import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

LightField _field(
  List<(Light, double, double)> lights, {
  double darkness = 0.8,
}) {
  final field = LightField()..darkness = darkness;
  for (final (light, x, y) in lights) {
    field.add(light, x, y, 0, 0, null);
  }
  return field;
}

void main() {
  test(
    'a bulb lights round itself, less the farther, nothing past its reach',
    () {
      final field = _field([(Light.point(radius: 100), 0, 0)]);
      final near = field.reach(0, 10, 0, 0);
      final far = field.reach(0, 60, 0, 0);
      expect(near, greaterThan(far));
      expect(far, greaterThan(0));
      expect(field.reach(0, 120, 0, 0), 0);
      // Depth is distance too: the same point farther in front of the line.
      expect(field.reach(0, 10, 0, 90), lessThan(near));
    },
  );

  test('a cone lights along its beam and eases out at its edge', () {
    final field = _field([
      (Light.cone(radius: 200, spread: 1.0), 0, 0),
    ]);
    expect(field.reach(0, 0, 100, 0), greaterThan(0), reason: 'straight down');
    expect(field.reach(0, 100, 0, 0), 0, reason: 'sideways, outside');
    final middle = field.reach(0, 0, 100, 0);
    final edge = field.reach(0, 100 * math.tan(0.45), 100, 0);
    expect(edge, lessThan(middle));
  });

  test('a shop window lights from all of it, a tube along its length', () {
    final field = _field([
      (Light.area(size: Vector2(100, 40), radius: 80), 0, 0),
      (Light.line(length: 100, radius: 80), 300, 0),
    ]);
    // In front of the window's corner it is as near as in front of its
    // middle: the whole window glows.
    expect(field.reach(0, 45, 30, 0), closeTo(field.reach(0, 0, 30, 0), 1e-6));
    expect(
      field.reach(1, 345, 30, 0),
      closeTo(field.reach(1, 300, 30, 0), 1e-6),
    );
    expect(field.reach(1, 300, 30, 0), greaterThan(field.reach(1, 400, 30, 0)));
  });

  test('the moon is the same everywhere', () {
    final field = _field([(Light.directional(intensity: 0.3), 0, 0)]);
    expect(field.reach(0, -500, 9000, 40), closeTo(0.3, 1e-6));
  });

  test('a lamp that lights itself comes on with the night', () {
    final lamp = Light.point(onAtDarkness: 0.4);
    expect(lamp.strengthAt(0, 0), 0, reason: 'day');
    expect(lamp.strengthAt(0, 0.2), closeTo(0.5, 1e-9));
    expect(lamp.strengthAt(0, 0.6), 1);
    final day = LightField()..darkness = 0;
    day.add(lamp, 0, 0, 0, 0, null);
    expect(day.count, 0, reason: 'an unlit light is left out');
  });

  test('a light is brighter than white when it is', () {
    final field = _field([(Light.point(intensity: 6, radius: 100), 0, 0)]);
    final out = LightSample();
    field.sample(1, 0, out);
    expect(out.light, greaterThan(1));
  });

  test(
    'a sample gives the mean colour; a drop flares in front of a lamp',
    () {
      final field = _field([
        (Light.point(color: const Color(0xFFFF0000), radius: 100), 0, 0),
      ]);
      final out = LightSample();
      field.sample(10, 0, out);
      expect(out.red, closeTo(1, 1e-6));
      expect(out.green, closeTo(0, 1e-6));
      final beside = LightSample();
      field.sample(20, 0, beside, forwardScatter: 0.7);
      final inFront = LightSample();
      field.sample(0, 0, inFront, inFront: 20, forwardScatter: 0.7);
      expect(inFront.scattered, greaterThan(beside.scattered));
    },
  );

  test('a shader gets a light as five vectors', () {
    final field = _field([(Light.point(intensity: 0.9, radius: 70), 30, 40)]);
    final into = Float32List(LightField.lightFloats);
    field.writeLight(0, into, 0);
    expect(into.sublist(0, 2), [30, 40], reason: 'where');
    expect(into[7], closeTo(0.9, 1e-6), reason: 'how strong');
    expect(into[8], 70, reason: 'how far it reaches');
  });

  test('a lamp shining down lights round its bulb too, near it', () {
    final field = _field([
      (Light.cone(radius: 300, spread: 1, spill: 0.8, spillRadius: 40), 0, 0),
    ]);
    // Above the bulb is outside the cone; the spill lights it near the
    // bulb, and not far off.
    expect(field.reach(0, 0, -20, 0), closeTo(0.8 * 0.25, 1e-6));
    expect(field.reach(0, 0, -60, 0), 0);
    expect(field.reach(0, 0, 100, 0), greaterThan(0.3), reason: 'the cone');
  });

  group('shadows', () {
    test(
      'an umbrella between a lamp and the rain under it shades the rain',
      () {
        final shadows = ShadowSet()
          ..capsule(-30, -100, 30, -100, radius: 5, thickness: 20);
        final field = _field([
          (Light.point(radius: 400, sourceRadius: 2), 0, -300),
        ])..shadows = shadows;
        expect(field.reach(0, 0, 0, 0), closeTo(0, 1e-3), reason: 'under it');
        final free = _field([
          (Light.point(radius: 400, sourceRadius: 2), 0, -300),
        ]);
        expect(
          field.reach(0, 200, 0, 0),
          closeTo(free.reach(0, 200, 0, 0), 1e-9),
          reason: 'beside it, as if nothing were there',
        );
      },
    );

    test('something at another depth does not shade a drop on the line', () {
      final shadows = ShadowSet()
        ..capsule(-30, -100, 30, -100, radius: 5, ahead: 200, thickness: 20);
      final field = _field([(Light.point(radius: 400), 0, -300)])
        ..shadows = shadows;
      expect(field.reach(0, 0, 0, 0), greaterThan(0.05));
    });

    test('a bigger source gives a softer edge', () {
      // A canopy 100 above the ground, a lamp 300 above: the hard shadow's
      // edge on the ground is at x = 30 * 300 / 200 = 45.
      double share(double source, double x) {
        final shadows = ShadowSet()
          ..capsule(-30, -100, 30, -100, radius: 1, thickness: 20);
        final lit = _field([
          (Light.point(radius: 600, sourceRadius: source), 0, -300),
        ])..shadows = shadows;
        final free = _field([(Light.point(radius: 600), 0, -300)]);
        return lit.reach(0, x, 0, 0) / free.reach(0, x, 0, 0);
      }

      expect(share(1, 30), closeTo(0, 1e-3), reason: 'well inside');
      expect(share(1, 70), closeTo(1, 1e-3), reason: 'well outside');
      // Just inside the edge a small source leaves it dark, a big one lights
      // it in part: the penumbra.
      expect(share(40, 40), greaterThan(share(1, 40) + 0.1));
    });
  });
}
