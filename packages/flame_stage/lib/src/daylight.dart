import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_stage/src/color_temperature.dart';
import 'package:flutter/foundation.dart' show immutable;

/// The light of the sky and the sun at a sun's elevation, under clouds, in
/// lamps (one lamp is about 20 lux, what a street lamp gives at its heart):
/// what an `Ambience` and a sun light are set from, so a scene's day comes
/// out of where the sun is rather than out of colours picked by hand.
///
/// Rough, physical in shape:
/// - the sun's direct light is thinned by the air it crosses (Kasten and
///   Young's air mass), reddening as the blue scatters out (Rayleigh);
/// - the sky's light is some 16 000 lux at a high sun; at sunset some
///   400; below the horizon it falls about tenfold every 2.5 degrees,
///   through civil and nautical twilight;
/// - a cloud layer of optical depth tau (`cloudOpticalDepth`) over the
///   part of the sky it covers lets the sun's disc through as
///   exp(-tau / sin h) (Beer-Lambert) and passes on, diffuse and grey, as
///   much of the light that falls on it as a scattering layer lets through
///   ([cloudTransmittance]): a quarter under a common overcast, a few
///   hundredths under a thunderhead;
/// - the night's floor is the moon's light through the clouds and a town's
///   glow, which they throw back down warm as much as they reflect.
@immutable
class Daylight {
  const Daylight({
    required this.sunElevation,
    required this.skyColor,
    required this.skyLight,
    required this.sunColor,
    required this.sunLight,
    required this.skyTop,
    required this.skyHorizon,
  });

  /// One lamp, lux.
  static const double lampLux = 20;

  /// How much of the light falling on a cloud layer of optical depth [tau]
  /// comes out underneath, diffuse: the two-stream answer for a layer that
  /// scatters without absorbing, 1 / (1 + 3/4 (1 - g) tau), with the
  /// droplets' asymmetry g of 0.85 - a quarter at tau 27, a common
  /// overcast; 0.08 at 100, a thunderhead.
  static double cloudTransmittance(double tau) =>
      1 / (1 + 0.75 * (1 - _asymmetry) * math.max(tau, 0));
  static const double _asymmetry = 0.85;

  /// The optical depth of the overcast a `cloudCover` alone stood for: a
  /// quarter of the clear day's light gets through it.
  static const double overcastOpticalDepth = 27;

  /// The day with the sun [sunElevation] degrees above the horizon (below
  /// 0 under it), clouds of optical depth `cloudOpticalDepth` over
  /// [cloudCover] of the sky (`0..1`), with a town's glow of [townGlowLux]
  /// reflected by them and the moon giving [moonLux].
  factory Daylight.at({
    required double sunElevation,
    double cloudCover = 0,
    double cloudOpticalDepth = overcastOpticalDepth,
    double townGlowLux = 1.5,
    double moonLux = 0.05,
  }) {
    final h = sunElevation;
    final cover = cloudCover.clamp(0.0, 1.0);
    final tau = math.max(cloudOpticalDepth, 0.0);
    // Through the clouds: the diffuse share, and the sun's disc.
    final through = cloudTransmittance(tau);
    final reflected = 1 - through;
    final up = math.sin(math.max(h, 0) * math.pi / 180);
    // Air mass (Kasten and Young) and what of the sun gets through it.
    final mass = h <= 0
        ? 40.0
        : 1 / (up + 0.50572 * math.pow(h + 6.07995, -1.6364));
    final direct = h <= 0 ? 0.0 : 127500 * math.exp(-0.21 * mass);
    // The clear sky's light on the ground.
    final clearSky = h > 0
        ? 400 + 16000 * math.sqrt(up)
        : 400 * math.pow(10, h / 2.5).toDouble();
    final clearTotal = direct * up + clearSky;
    final sky = (1 - cover) * clearSky + cover * through * clearTotal;
    final disc = up <= 0 ? 0.0 : math.exp(-tau / math.max(up, 0.05));
    final sun = direct * ((1 - cover) + cover * disc);
    final night =
        moonLux * ((1 - cover) + cover * through) +
        townGlowLux * cover * reflected;
    final skyLux = math.max(sky, 0) + night;

    // Colours: the sun reddens through the air; the clear sky is blue, the
    // twilight sky bluer, an overcast one grey, a town's glow on clouds
    // sodium orange.
    final sunColor = _transmitted(mass);
    final clearColor = h > 0 ? colorOfKelvin(11000) : colorOfKelvin(16000);
    final skyColorDay = _mix(clearColor, colorOfKelvin(6800), cover);
    final skyColor = _mixWeighted([
      (skyColorDay, math.max(sky, 0)),
      (colorOfKelvin(4100), moonLux),
      (colorOfKelvin(2200), townGlowLux * cover * reflected),
    ]);

    // The sky as the eye sees it against a white thing in the same light:
    // its glow over the light everything gets. Low, the sun warms the
    // horizon.
    final total = skyLux + sun * up;
    final glow = (skyLux / math.max(total, 1e-6)).clamp(0.0, 1.0);
    // The low sun's warmth reaches the horizon as much as the clouds let
    // the light through.
    final warm = (h > -6 && h < 12)
        ? (1 - (h - 3).abs() / 9).clamp(0.0, 1.0) *
              ((1 - cover) + cover * through)
        : 0.0;
    final top = _scale(skyColor, 0.55 + 0.25 * glow);
    final horizon = _scale(
      _mix(skyColor, _mix(sunColor, const Color(0xFFFF9A6A), 0.4), warm * 0.8),
      0.75 + 0.25 * glow,
    );
    return Daylight(
      sunElevation: h,
      skyColor: skyColor,
      skyLight: skyLux / lampLux,
      sunColor: sunColor,
      sunLight: sun / lampLux,
      skyTop: top,
      skyHorizon: horizon,
    );
  }

  /// The sun's elevation it was worked out for, degrees.
  final double sunElevation;

  /// The colour of the sky's light.
  final Color skyColor;

  /// How much light the sky gives, in lamps.
  final double skyLight;

  /// The colour of the sun's direct light.
  final Color sunColor;

  /// How much direct light the sun gives, on a surface facing it, in lamps.
  final double sunLight;

  /// The sky at the top of the view and at the horizon, as the eye sees it
  /// beside a white thing in the scene's light.
  final Color skyTop;
  final Color skyHorizon;

  static Color _transmitted(double mass) {
    // Optical depth per channel for clean air at one air mass.
    double channel(double tau) => math.exp(-tau * mass);
    final r = channel(0.06);
    final g = channel(0.12);
    final b = channel(0.25);
    final top = math.max(r, math.max(g, b));
    return Color.from(alpha: 1, red: r / top, green: g / top, blue: b / top);
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  static Color _scale(Color c, double by) => Color.from(
    alpha: 1,
    red: (c.r * by).clamp(0.0, 1.0),
    green: (c.g * by).clamp(0.0, 1.0),
    blue: (c.b * by).clamp(0.0, 1.0),
  );

  static Color _mixWeighted(List<(Color, double)> parts) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var w = 0.0;
    for (final (c, weight) in parts) {
      if (weight <= 0) {
        continue;
      }
      r += c.r * weight;
      g += c.g * weight;
      b += c.b * weight;
      w += weight;
    }
    if (w <= 0) {
      return const Color(0xFFFFFFFF);
    }
    final top = math.max(r, math.max(g, b)) / w;
    return Color.from(
      alpha: 1,
      red: r / w / top,
      green: g / w / top,
      blue: b / w / top,
    );
  }
}
