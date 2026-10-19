import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// Something per colour: red (about 650 nm), green (550), blue (450).
@immutable
class Rgb {
  const Rgb(this.r, this.g, this.b);

  /// The same for every colour.
  const Rgb.all(double v) : r = v, g = v, b = v;

  final double r;
  final double g;
  final double b;

  Rgb operator +(Rgb o) => Rgb(r + o.r, g + o.g, b + o.b);
  Rgb operator *(double k) => Rgb(r * k, g * k, b * k);

  /// [f] of each colour.
  Rgb map(double Function(double) f) => Rgb(f(r), f(g), f(b));

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'Rgb($r, $g, $b)';
}

/// Water as a medium light goes into: how much of it its surface mirrors,
/// how fast it takes light away going down and back, and how much it sends
/// back up from its depth.
///
/// One model for a film on asphalt, a puddle and a pond: what shows under
/// the mirror is the bottom, through the water there and back, and the
/// glow of the water itself, scattered back up from as much of it as there
/// is. A film or a puddle a few centimetres deep lets the asphalt show
/// through, lamp light and all; a pond a metre deep hides its bed and
/// shows its own colour.
///
/// Optics, per colour:
/// - the surface mirrors by Fresnel, Schlick's form from the refractive
///   index [refractiveIndex] ([f0]);
/// - light going through d metres of it keeps exp(-c d), c the absorption
///   [absorption] and the scattering [scattering] together (Beer-Lambert);
///   it goes down and up along the refracted way ([transmission]);
/// - deep, it sends back a share of the light falling on it
///   ([deepReflectance]): pi Rrs, Rrs = 0.0949 u + 0.0794 u^2 with
///   u = bb / (a + bb), bb the share [backscatterShare] of the scattering
///   that goes back (Gordon et al. 1988).
@immutable
class WaterMedium {
  const WaterMedium({
    required this.absorption,
    required this.scattering,
    this.backscatterShare = 0.5,
    this.refractiveIndex = 1.333,
  });

  /// Rain and clear water: pure water's own absorption (Pope and Fry 1997)
  /// and scattering, half of it back (molecules scatter as much back as
  /// forward). A metre of it is near clear; deep, it is dark blue.
  static const clear = WaterMedium(
    absorption: Rgb(0.34, 0.057, 0.015),
    scattering: Rgb(0.0009, 0.0019, 0.0047),
  );

  /// A park pond: pure water with what dissolves in it from the leaves (a
  /// brown that takes the blue: about 0.9 per metre at 450 nm, falling off
  /// as exp(-0.015 per nm) towards the red) and algae and silt in it (some
  /// 2 per metre of scattering, a fiftieth of it back). Its bed is gone
  /// under half a metre; it shows dark green-brown.
  static const pond = WaterMedium(
    absorption: Rgb(0.34 + 0.05 + 0.1, 0.057 + 0.19, 0.015 + 0.86),
    scattering: Rgb(2, 2, 2),
    backscatterShare: 0.015,
  );

  /// Per metre, what it takes of each colour's light.
  final Rgb absorption;

  /// Per metre, what it scatters of each colour's light.
  final Rgb scattering;

  /// The share of what it scatters that goes back.
  final double backscatterShare;

  /// Its refractive index.
  final double refractiveIndex;

  /// How much its surface mirrors looked at straight down.
  double get f0 {
    final k = (refractiveIndex - 1) / (refractiveIndex + 1);
    return k * k;
  }

  /// How much its surface mirrors seen at an angle whose sine above it is
  /// [sinElevation] (Schlick).
  double fresnel(double sinElevation) {
    final c = 1 - sinElevation.clamp(0.0, 1.0);
    final c2 = c * c;
    return f0 + (1 - f0) * c2 * c2 * c;
  }

  /// Per metre, what light going straight through loses.
  Rgb get attenuation => absorption + scattering;

  /// The cosine of the refracted way under a surface seen at an angle
  /// whose sine above it is [sinElevation] (Snell).
  double cosRefracted(double sinElevation) {
    final s = sinElevation.clamp(0.0, 1.0);
    final across = (1 - s * s) / (refractiveIndex * refractiveIndex);
    return math.sqrt(math.max(1 - across, 0));
  }

  /// What of the bottom's light comes back up through [depthM] metres of
  /// it, seen at an angle whose sine above it is [sinElevation]: down and
  /// up along the refracted way.
  Rgb transmission(double depthM, double sinElevation) {
    final path = 2 * math.max(depthM, 0) / cosRefracted(sinElevation);
    return attenuation.map((c) => math.exp(-c * path));
  }

  /// The share of the light falling on it that deep water sends back up
  /// out of its depth.
  Rgb get deepReflectance {
    double of(double a, double b) {
      final bb = b * backscatterShare;
      final u = bb / math.max(a + bb, 1e-9);
      return math.pi * (0.0949 * u + 0.0794 * u * u);
    }

    return Rgb(
      of(absorption.r, scattering.r),
      of(absorption.g, scattering.g),
      of(absorption.b, scattering.b),
    );
  }
}
