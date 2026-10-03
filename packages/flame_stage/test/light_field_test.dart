import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// [lights] under a night sky: a little blue light, the eye adapted to a
/// lamp's worth.
LightField _field(
  List<(Light, double, double)> lights, {
  double skyLight = 0.2,
}) {
  final field = LightField()
    ..beginUnder(sky: const Color(0xFFFFFFFF), skyLight: skyLight);
  for (final (light, x, y) in lights) {
    field.add(light, x, y, 0, 0, null);
  }
  return field..finish();
}

void main() {
  test(
    'the eye adapts to brighter light quickly, to dimmer slowly',
    () {
      final field = LightField();
      void under(double skyLight) => field.beginUnder(
        sky: const Color(0xFFFFFFFF),
        skyLight: skyLight,
        adaptsIn: 1,
        darkAdaptsIn: 40,
      );
      under(100);
      field.finish();
      final bright = field.exposure;
      // The sky falls tenfold: a second on, the eye has barely begun.
      under(10);
      field.finish(1);
      final share =
          (math.log(field.exposure) - math.log(bright)) /
          (math.log(10 * bright) - math.log(bright));
      expect(share, closeTo(1 - math.exp(-1 / 40), 1e-6));
      // Back to bright: a second on, most of the way.
      under(100);
      final dark = field.exposure;
      field.finish(1);
      final back =
          (math.log(field.exposure) - math.log(dark)) /
          (math.log(bright) - math.log(dark));
      expect(back, closeTo(1 - math.exp(-1), 1e-6));
    },
  );

  test('lamps fill what the sky leaves up to white, never past it', () {
    expect(LightField.fill(0.3, 0), closeTo(0.3, 1e-12), reason: 'no lamp');
    expect(LightField.fill(1, 5), 1, reason: 'nothing left to fill');
    // Faint, in proportion; strong, ever nearer white, still rising.
    expect(LightField.fill(0, 0.01), closeTo(0.01, 1e-4));
    var last = 0.0;
    for (var lamps = 0.5; lamps <= 8; lamps += 0.5) {
      final shown = LightField.fill(0.2, lamps);
      expect(shown, greaterThan(last));
      expect(shown, lessThan(1));
      last = shown;
    }
  });

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

  test('the moon adds to the sky, the same everywhere', () {
    final field = _field([
      (Light.directional(color: const Color(0xFFFFFFFF), intensity: 0.3), 0, 0),
    ]);
    expect(field.count, 0, reason: 'not a light of the field');
    expect(field.skyLevel, closeTo(0.5, 1e-6));
    final out = LightSample();
    field.sample(-500, 9000, out);
    expect(out.light, closeTo(0.5, 1e-6));
  });

  test('a lamp with a sensor comes on as the sky darkens', () {
    final lamp = Light.point(switchOnBelow: 2);
    expect(lamp.strengthAt(0, 30), 0, reason: 'day');
    expect(lamp.strengthAt(0, 3), closeTo(0.5, 1e-9), reason: 'dusk');
    expect(lamp.strengthAt(0, 0.1), 1, reason: 'night');
    final day = LightField()
      ..beginUnder(sky: const Color(0xFFFFFFFF), skyLight: 30);
    day.add(lamp, 0, 0, 0, 0, null);
    expect(day.count, 0, reason: 'an unlit light is left out');
  });

  test('the eye adapts to the sky: by day a lamp is a speck', () {
    final lamp = Light.point(radius: 100);
    final night = _field([(lamp, 0, 0)]);
    final day = _field([(lamp, 0, 0)], skyLight: 40);
    final atNight = LightSample();
    final byDay = LightSample();
    night.sample(10, 0, atNight);
    day.sample(10, 0, byDay);
    expect(night.exposure, 1, reason: 'no brighter than a lamp adapts to');
    expect(day.exposure, closeTo(1 / 40, 1e-9));
    expect(atNight.added, greaterThan(0.5));
    expect(byDay.added, lessThan(0.03));
    expect(byDay.light, closeTo(1, 0.03), reason: 'the sky, as white');
    expect(atNight.light - atNight.added, closeTo(0.2, 1e-6));
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

  test('the eye adapts to the lamplight in view, not a speck of it', () {
    const view = Rect.fromLTWH(0, 0, 400, 300);
    LightField under(double radius) {
      final field = LightField()
        ..beginUnder(
          sky: const Color(0xFFFFFFFF),
          skyLight: 0.05,
          adaptation: 0.01,
        )
        ..add(Light.point(radius: radius, intensity: 2), 200, 150, 0, 0, null);
      return field..finish(0, view);
    }

    final dark = LightField()
      ..beginUnder(
        sky: const Color(0xFFFFFFFF),
        skyLight: 0.05,
        adaptation: 0.01,
      )
      ..finish(0, view);
    expect(dark.exposure, closeTo(20, 1e-6), reason: 'the sky alone');
    // A pool filling the view: the eye takes it in, as on a lit street.
    expect(under(400).exposure, lessThan(dark.exposure / 4));
    // A distant bulb: next to nothing.
    expect(under(20).exposure, greaterThan(dark.exposure * 0.8));
  });

  test("in thick air at night the eye adapts to the lamps' glow in it", () {
    const view = Rect.fromLTWH(0, 0, 400, 300);
    LightField under({required double glow}) {
      final field = LightField()
        ..beginUnder(
          sky: const Color(0xFFFFFFFF),
          skyLight: 0.05,
          adaptation: 0.01,
          glow: glow,
        )
        ..airDepth = 20
        ..airVisibility = 60;
      for (var x = 50.0; x < 400; x += 100) {
        field.add(Light.point(radius: 60, intensity: 2), x, 150, 0, 0, null);
      }
      return field..finish(0, view);
    }

    final clear = under(glow: 0);
    final downpour = under(glow: 0.9);
    // The air before the street holds the lamps' light: the eye takes it
    // in, and sees the scene darker for it.
    expect(downpour.exposure, lessThan(clear.exposure * 0.8));
  });

  test("the glow along the eye's way sums the falloff past a lamp", () {
    // (1 - r/R)^2 along a line passing b from the light, summed by hand.
    double summed(double b, double radius) {
      const n = 20000;
      final half = math.sqrt(radius * radius - b * b);
      var total = 0.0;
      for (var i = 0; i < n; i++) {
        final t = -half + (i + 0.5) * 2 * half / n;
        final r = math.sqrt(b * b + t * t);
        final f = 1 - r / radius;
        total += f * f * 2 * half / n;
      }
      return total;
    }

    for (final b in [0.5, 2.0, 5.0, 9.0]) {
      expect(
        LightField.glowLength(b, 10),
        closeTo(summed(b, 10), 1e-3),
        reason: 'b $b',
      );
    }
    expect(LightField.glowLength(10, 10), 0);
  });

  test('the capsules nearest the middle of the view come first', () {
    final shadows = ShadowSet()
      ..capsule(900, 0, 900, 10, radius: 1)
      ..capsule(10, 0, 10, 10, radius: 1)
      ..capsule(400, 0, 400, 10, radius: 1);
    shadows.nearestFirst(0, 5);
    expect(
      [for (var i = 0; i < 3; i++) shadows.data[i * ShadowSet.stride]],
      [
        10,
        400,
        900,
      ],
    );
  });
}
