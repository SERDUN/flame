import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// Where the sun and the moon stand in a place's sky at a moment, and how
/// much of the moon is lit and how much light it gives: a low-precision
/// ephemeris (the sun's and the moon's mean elements and their largest
/// terms, after Meeus) - good to about a degree, which a scene needs.
///
/// The moment is a day of a year and the local solar time (`solarHour`, 12
/// when the sun is due south of a northern place): what a scene knows of its
/// day. Angles are radians; azimuths are compass bearings, from north
/// through east.
@immutable
class Celestial {
  /// The sky over [latitudeDeg] on day [dayOfYear] of [year] at [solarHour].
  factory Celestial.at({
    required int year,
    required int dayOfYear,
    required double solarHour,
    required double latitudeDeg,
  }) {
    // Days from J2000.0 (2000-01-01 12:00 UT), the solar time taken as UT:
    // an hour off moves the moon half a degree.
    final day =
        DateTime.utc(year).difference(_j2000).inSeconds / 86400 +
        (dayOfYear - 1) +
        solarHour / 24;
    final epsilon = _rad(23.439 - 0.0000004 * day);
    // The sun's ecliptic longitude.
    final mean = _rad(280.460 + 0.9856474 * day);
    final anomaly = _rad(357.528 + 0.9856003 * day);
    final sunLongitude =
        mean +
        _rad(1.915) * math.sin(anomaly) +
        _rad(0.020) * math.sin(2 * anomaly);
    // The moon's, and its latitude off the ecliptic.
    final moonMean = _rad(218.316 + 13.176396 * day);
    final moonAnomaly = _rad(134.963 + 13.064993 * day);
    final node = _rad(93.272 + 13.229350 * day);
    final moonLongitude = moonMean + _rad(6.289) * math.sin(moonAnomaly);
    final moonLatitude = _rad(5.128) * math.sin(node);
    final (sunRa, sunDec) = _equatorial(sunLongitude, 0, epsilon);
    final (moonRa, moonDec) = _equatorial(moonLongitude, moonLatitude, epsilon);
    final latitude = _rad(latitudeDeg);
    // The sun's hour angle is the solar time; the sidereal time follows from
    // it, and the moon's hour angle from that.
    final sunHour = _rad(15 * (solarHour - 12));
    final sidereal = sunRa + sunHour;
    final moonHour = sidereal - moonRa;
    final (sunAlt, sunAz) = _horizontal(sunHour, sunDec, latitude);
    final (moonAlt, moonAz) = _horizontal(moonHour, moonDec, latitude);
    // How far the moon stands from the sun, and so how much of it is lit.
    final elongation = math.acos(
      (math.cos(moonLatitude) * math.cos(moonLongitude - sunLongitude)).clamp(
        -1.0,
        1.0,
      ),
    );
    final phase = math.pi - elongation;
    return Celestial._(
      sunAltitude: sunAlt,
      sunAzimuth: sunAz,
      moonAltitude: moonAlt,
      moonAzimuth: moonAz,
      moonPhaseAngle: phase,
      sidereal: sidereal,
      latitude: latitude,
    );
  }

  const Celestial._({
    required this.sunAltitude,
    required this.sunAzimuth,
    required this.moonAltitude,
    required this.moonAzimuth,
    required this.moonPhaseAngle,
    required this.sidereal,
    required this.latitude,
  });

  /// The local sidereal time, radians: which right ascension is due south.
  final double sidereal;

  /// The place's latitude, radians.
  final double latitude;

  /// Where a star at right ascension [ra] and declination [dec] stands now:
  /// its altitude and bearing.
  (double, double) horizontalOf(double ra, double dec) =>
      _horizontal(sidereal - ra, dec, latitude);

  static final DateTime _j2000 = DateTime.utc(2000, 1, 1, 12);

  /// The sun's height over the horizon and its bearing.
  final double sunAltitude;
  final double sunAzimuth;

  /// The moon's.
  final double moonAltitude;
  final double moonAzimuth;

  /// The angle at the moon between the sun and the eye: 0 full, pi new.
  final double moonPhaseAngle;

  /// The share of the moon's disc lit, `0..1`.
  double get moonLit => (1 + math.cos(moonPhaseAngle)) / 2;

  /// The moon's angular radius, radians (its mean: about a quarter of a
  /// degree).
  static const double moonRadius = 0.00452;

  /// The full moon's light outside the air, square on, lux.
  static const double fullMoonLux = 0.267;

  /// How much the air takes of light coming through it straight down,
  /// magnitudes (a clear night's, in the visual).
  static const double extinctionPerAirmass = 0.2;

  /// The moon's light on level ground under a clear sky, lux: the full
  /// moon's, dimmer by its phase (Allen: 0.026 |i| + 4e-9 i^4 magnitudes, i
  /// in degrees), by how low it stands, and by the air on the way down.
  double get moonLux {
    if (moonAltitude <= 0) {
      return 0;
    }
    final i = moonPhaseAngle * 180 / math.pi;
    final phase = math
        .pow(10, -0.4 * (0.026 * i.abs() + 4e-9 * math.pow(i, 4)))
        .toDouble();
    final through = math
        .pow(10, -0.4 * extinctionPerAirmass * airmass(moonAltitude))
        .toDouble();
    return fullMoonLux * phase * math.sin(moonAltitude) * through;
  }

  /// How much air light comes through from [altitude] up, against straight
  /// up (Kasten and Young).
  static double airmass(double altitude) {
    final degrees = math.max(altitude * 180 / math.pi, -1.0);
    return 1 /
        (math.sin(math.max(altitude, -0.017)) +
            0.50572 * math.pow(degrees + 6.07995, -1.6364));
  }

  /// The local solar time at which the sun stands [elevationDeg] up on day
  /// [dayOfYear] at [latitudeDeg]: in the afternoon while [setting], in the
  /// morning otherwise. Past what the sun reaches that day, noon or
  /// midnight.
  static double solarHourOf({
    required double elevationDeg,
    required int dayOfYear,
    required double latitudeDeg,
    required bool setting,
  }) {
    final declination =
        _rad(-23.44) * math.cos(2 * math.pi / 365 * (dayOfYear + 10));
    final latitude = _rad(latitudeDeg);
    final c =
        (math.sin(_rad(elevationDeg)) -
            math.sin(latitude) * math.sin(declination)) /
        (math.cos(latitude) * math.cos(declination));
    final hour = math.acos(c.clamp(-1.0, 1.0)) * 12 / math.pi;
    return setting ? 12 + hour : 12 - hour;
  }

  static double _rad(double degrees) => degrees * math.pi / 180;

  /// Right ascension and declination from ecliptic longitude and latitude.
  static (double, double) _equatorial(
    double longitude,
    double latitude,
    double epsilon,
  ) {
    final dec = math.asin(
      (math.sin(latitude) * math.cos(epsilon) +
              math.cos(latitude) * math.sin(epsilon) * math.sin(longitude))
          .clamp(-1.0, 1.0),
    );
    final ra = math.atan2(
      math.sin(longitude) * math.cos(epsilon) -
          math.tan(latitude) * math.sin(epsilon),
      math.cos(longitude),
    );
    return (ra, dec);
  }

  /// Altitude and bearing from hour angle and declination at [latitude].
  static (double, double) _horizontal(
    double hour,
    double dec,
    double latitude,
  ) {
    final altitude = math.asin(
      (math.sin(latitude) * math.sin(dec) +
              math.cos(latitude) * math.cos(dec) * math.cos(hour))
          .clamp(
            -1.0,
            1.0,
          ),
    );
    final azimuth = math.atan2(
      -math.cos(dec) * math.sin(hour),
      math.sin(dec) * math.cos(latitude) -
          math.cos(dec) * math.sin(latitude) * math.cos(hour),
    );
    return (altitude, (azimuth + 2 * math.pi) % (2 * math.pi));
  }
}

/// The stars of the sky as the eye sees them: a fixed sky of stars by
/// brightness as the real one has them (some 9000 to the sixth magnitude,
/// three times as many each magnitude fainter), and the faintest one sees
/// against a sky of a given brightness (Schaefer).
class StarSky {
  /// Every star to [faintest] magnitude, placed by [seed] over the sphere.
  StarSky({required int seed, this.faintest = 6.5}) {
    final random = math.Random(seed);
    final count = (_toSixAndHalf * math.pow(10, 0.5 * (faintest - 6.5)))
        .round();
    for (var i = 0; i < count; i++) {
      // Even over the sphere: declination by its sine.
      ra.add(random.nextDouble() * 2 * math.pi);
      dec.add(math.asin(2 * random.nextDouble() - 1));
      // N(< m) grows tenfold every two magnitudes.
      magnitude.add(
        faintest +
            2 * math.log(math.max(random.nextDouble(), 1e-12)) / math.ln10,
      );
    }
  }

  /// Stars to magnitude 6.5 over the whole sky.
  static const int _toSixAndHalf = 9100;

  /// The faintest star kept.
  final double faintest;

  /// Each star's right ascension, declination (radians) and magnitude.
  final List<double> ra = [];
  final List<double> dec = [];
  final List<double> magnitude = [];

  /// The faintest star the eye sees against a sky of [luminance], cd/m2:
  /// some 6.4 under a dark country sky (0.0002), 4 or 5 in a town, the first
  /// stars at dusk (Schaefer 1990).
  static double limitingMagnitude(double luminance) {
    final mu = 12.603 - 2.5 * math.log(math.max(luminance, 1e-9)) / math.ln10;
    return 7.93 - 5 * math.log(math.pow(10, 4.316 - mu / 5) + 1) / math.ln10;
  }
}
