import 'dart:math' as math;

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

int _dayOfYear(int year, int month, int day) =>
    DateTime.utc(year, month, day).difference(DateTime.utc(year)).inDays + 1;

double _deg(double radians) => radians * 180 / math.pi;

void main() {
  group('Celestial', () {
    test('the noon sun stands as high as the season and the latitude say', () {
      // At an equinox noon at 50 N, 90 - 50 = 40 degrees up, due south.
      final equinox = Celestial.at(
        year: 2026,
        dayOfYear: _dayOfYear(2026, 3, 20),
        solarHour: 12,
        latitudeDeg: 50,
      );
      expect(_deg(equinox.sunAltitude), closeTo(40, 1));
      expect(_deg(equinox.sunAzimuth), closeTo(180, 2));
      // At midsummer 23.4 higher; at midwinter as much lower.
      final summer = Celestial.at(
        year: 2026,
        dayOfYear: _dayOfYear(2026, 6, 21),
        solarHour: 12,
        latitudeDeg: 50,
      );
      expect(_deg(summer.sunAltitude), closeTo(63.4, 1));
      final winter = Celestial.at(
        year: 2026,
        dayOfYear: _dayOfYear(2026, 12, 21),
        solarHour: 12,
        latitudeDeg: 50,
      );
      expect(_deg(winter.sunAltitude), closeTo(16.6, 1));
    });

    test('the moon is new at a solar eclipse and full a fortnight later', () {
      // The total eclipse of 8 April 2024, the full moon of 23 April 2024.
      final eclipse = Celestial.at(
        year: 2024,
        dayOfYear: _dayOfYear(2024, 4, 8),
        solarHour: 18,
        latitudeDeg: 40,
      );
      expect(eclipse.moonLit, lessThan(0.01));
      final full = Celestial.at(
        year: 2024,
        dayOfYear: _dayOfYear(2024, 4, 23),
        solarHour: 23.8,
        latitudeDeg: 40,
      );
      expect(full.moonLit, greaterThan(0.98));
    });

    test(
      'a high full moon lights the ground with a fifth of a lux',
      () {
        // 26 October 2026 is a full moon; at midnight high over 50 N.
        final full = Celestial.at(
          year: 2026,
          dayOfYear: _dayOfYear(2026, 10, 26),
          solarHour: 0.5,
          latitudeDeg: 50.45,
        );
        expect(_deg(full.moonAltitude), greaterThan(30));
        expect(full.moonLux, inInclusiveRange(0.08, 0.27));
        final down = Celestial.at(
          year: 2026,
          dayOfYear: _dayOfYear(2026, 10, 26),
          solarHour: 12,
          latitudeDeg: 50.45,
        );
        expect(
          down.moonLux,
          0,
          reason: 'a full moon at noon is under the horizon',
        );
      },
    );

    test('the time of day follows from where the sun stands', () {
      const day = 295;
      final hour = Celestial.solarHourOf(
        elevationDeg: -2,
        dayOfYear: day,
        latitudeDeg: 50.45,
        setting: true,
      );
      final sky = Celestial.at(
        year: 2026,
        dayOfYear: day,
        solarHour: hour,
        latitudeDeg: 50.45,
      );
      expect(_deg(sky.sunAltitude), closeTo(-2, 1));
      expect(hour, inInclusiveRange(16.5, 18.5));
      expect(
        _deg(sky.sunAzimuth),
        inInclusiveRange(230, 270),
        reason: 'an October sunset in the south west',
      );
    });

    test('the north star stands as high as the latitude', () {
      final sky = Celestial.at(
        year: 2026,
        dayOfYear: 100,
        solarHour: 22,
        latitudeDeg: 50,
      );
      final (altitude, azimuth) = sky.horizontalOf(0, math.pi / 2);
      expect(_deg(altitude), closeTo(50, 1e-6));
      expect(math.min(azimuth, 2 * math.pi - azimuth), lessThan(1e-6));
    });
  });

  group('StarSky', () {
    test('as many stars as the real sky has to each magnitude', () {
      final sky = StarSky(seed: 1);
      int brighterThan(double m) => sky.magnitude.where((x) => x < m).length;
      expect(sky.magnitude.length, closeTo(9100, 1));
      expect(brighterThan(4), inInclusiveRange(380, 650));
      expect(brighterThan(1), lessThan(40));
    });

    test(
      'a dark sky shows the sixth magnitude, a town the fourth, dusk the first',
      () {
        expect(StarSky.limitingMagnitude(0.0002), closeTo(6.4, 0.3));
        expect(StarSky.limitingMagnitude(0.01), inInclusiveRange(3.5, 5));
        expect(StarSky.limitingMagnitude(2), lessThan(2));
      },
    );
  });
}
