import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('noon is tens of thousands of lux, a clear night a fraction of one', () {
    final noon = Daylight.at(sunElevation: 60);
    final sunset = Daylight.at(sunElevation: 0);
    final civil = Daylight.at(sunElevation: -6, townGlowLux: 0, moonLux: 0);
    final night = Daylight.at(sunElevation: -30, townGlowLux: 0);
    expect(
      (noon.skyLight + noon.sunLight) * Daylight.lampLux,
      greaterThan(80000),
    );
    expect(sunset.skyLight * Daylight.lampLux, closeTo(400, 1));
    // The end of civil twilight: a few lux.
    expect(civil.skyLight * Daylight.lampLux, inInclusiveRange(1, 5));
    expect(night.skyLight * Daylight.lampLux, closeTo(0.05, 0.01));
  });

  test('the low sun is red, the high sun white', () {
    final high = Daylight.at(sunElevation: 60).sunColor;
    final low = Daylight.at(sunElevation: 2).sunColor;
    expect(high.b, greaterThan(0.75), reason: 'about 5800 K');
    expect(low.b, lessThan(low.r * 0.6));
  });

  test('clouds take the sun away and make the sky grey and dimmer', () {
    final clear = Daylight.at(sunElevation: 30);
    final overcast = Daylight.at(sunElevation: 30, cloudCover: 1);
    expect(overcast.sunLight, closeTo(0, 1e-9));
    expect(
      overcast.skyLight,
      lessThan(clear.skyLight + clear.sunLight * 0.5),
    );
    final grey = overcast.skyColor;
    expect((grey.r - grey.b).abs(), lessThan(0.12));
  });

  test(
    'a thicker cloud lets less of the day through, and a thin one the sun',
    () {
      expect(
        Daylight.cloudTransmittance(Daylight.overcastOpticalDepth),
        closeTo(0.25, 0.01),
      );
      expect(Daylight.cloudTransmittance(100), closeTo(0.08, 0.005));
      final overcast = Daylight.at(sunElevation: 30, cloudCover: 1);
      final thunderhead = Daylight.at(
        sunElevation: 30,
        cloudCover: 1,
        cloudOpticalDepth: 150,
      );
      expect(thunderhead.skyLight, lessThan(overcast.skyLight / 3));
      final haze = Daylight.at(
        sunElevation: 30,
        cloudCover: 1,
        cloudOpticalDepth: 0.5,
      );
      expect(
        haze.sunLight,
        greaterThan(0),
        reason: 'the disc through a thin veil',
      );
      // At night a thick cloud throws more of the town's glow back down.
      final thin = Daylight.at(
        sunElevation: -25,
        cloudCover: 1,
        cloudOpticalDepth: 5,
      );
      final thick = Daylight.at(
        sunElevation: -25,
        cloudCover: 1,
        cloudOpticalDepth: 150,
      );
      expect(thick.skyLight, greaterThan(thin.skyLight));
    },
  );

  test('the harder it rains, the thicker the cloud it falls from', () {
    expect(cloudOpticalDepthOfRain(0), Daylight.overcastOpticalDepth);
    expect(cloudOpticalDepthOfRain(6), greaterThan(cloudOpticalDepthOfRain(1)));
    expect(cloudOpticalDepthOfRain(40), greaterThan(150));
  });

  test("a cloudy town's night is lit orange by its own glow", () {
    final night = Daylight.at(sunElevation: -25, cloudCover: 1);
    expect(night.skyColor.r, greaterThan(night.skyColor.b));
    expect(night.skyLight, greaterThan(0.05));
  });

  test('the sun shades what stands behind a post, and lights the rest', () {
    final shadows = ShadowSet()
      // A post 2 m tall at x 0, on the street line.
      ..capsule(0, -2, 0, 0, radius: 0.1, thickness: 0.2);
    final field = LightField()
      ..shadows = shadows
      ..beginUnder(sky: const Color(0xFFFFFFFF), skyLight: 10)
      ..add(
        // Low from the left, going right and a little down.
        Light.sun(toward: Vector3(1, 0.5, 0)),
        0,
        0,
        0,
        0,
        null,
      )
      ..finish();
    expect(field.count, 1, reason: 'a sun is kept, not folded into the sky');
    // At the post's height, 2 m on to the right: in its shadow.
    expect(field.reach(0, 2, -0.5, 0), closeTo(0, 0.05));
    // To its left, toward the sun: lit.
    expect(field.reach(0, -2, -0.5, 0), closeTo(1, 1e-6));
    // A sun is light for the eye to adapt to.
    expect(field.exposure, lessThan(1 / 10));
  });
}
