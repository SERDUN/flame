import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// Where a point of the scene is, in metres: x along the road, ahead in
/// front of the street line (behind it, negative; the eye stands some
/// distance in front), height above the ground.
typedef AirPoint = ({double x, double ahead, double height});

/// A body of air thicker than the rest - fog rolling in over a pond, the
/// rain of a storm cell - lying past an edge across the ground and thinning
/// with height.
///
/// Its edge is a line on the ground: the points whose position along
/// [angle] (0 along the road, pi/2 away from the eye) is [at]; it lies on the
/// far side of it, eased in over [widthM]. The edge leans [slant] metres
/// along that way per metre up (a rain cell's, as the wind carries the
/// drops). It is a layer on the ground up to its top [topM], thinning out
/// over [topWidthM] round it (a logistic step): a fog lies under a warmer
/// air that keeps it down - a ground fog a metre over the ground and the
/// water with the air clear above, a deep fog tens of metres up.
@immutable
class AirBank {
  const AirBank({
    required this.extinction,
    this.at = double.negativeInfinity,
    this.angle = 0,
    this.widthM = 20,
    this.slant = 0,
    this.topM = 50,
    this.topWidthM = 10,
  });

  /// Per metre, what it adds to the air's extinction at the ground, inside
  /// it: 3.912 over the visibility it alone would leave (Koschmieder).
  final double extinction;

  /// Where its edge is, m along [angle]; minus infinity: everywhere.
  final double at;

  /// Which way it lies past its edge, radians: 0 on along the road, pi back
  /// along it, pi/2 away from the eye.
  final double angle;

  /// How far it eases in over its edge, m.
  final double widthM;

  /// How far its edge leans along [angle] per metre up.
  final double slant;

  /// How high it reaches, m: where it is half as thick as at the ground.
  final double topM;

  /// How far round its top it thins out, m.
  final double topWidthM;

  /// How much of it there is at [height] above the ground, `0..1`.
  double _layer(double height) {
    final s = math.max(topWidthM, 1e-3) / 4;
    return 1 / (1 + math.exp(((height - topM) / s).clamp(-60.0, 60.0)));
  }

  /// The layer summed from the ground up to [height]: the integral of
  /// [_layer], h - s ln(1 + e^((h - top) / s)).
  double _layerUpTo(double height) {
    final s = math.max(topWidthM, 1e-3) / 4;
    final x = (height - topM) / s;
    // ln(1 + e^x), kept finite both ways.
    final soft = x > 30 ? x : math.log(1 + math.exp(math.max(x, -60)));
    return height - s * soft;
  }

  /// Whether it lies everywhere, with no edge across the ground.
  bool get everywhere => at == double.negativeInfinity;

  /// Where [p] is across its edge: 0 before it, 1 past it, eased between.
  double _across(AirPoint p) =>
      (p.x * math.cos(angle) +
              p.ahead * math.sin(angle) -
              slant * p.height -
              at) /
          math.max(widthM, 1e-6) +
      0.5;

  /// The smoothstep summed from 0 up to [u]: u^3 - u^4 / 2 over its ease.
  static double _easedUpTo(double u) {
    if (u <= 0) {
      return 0;
    }
    if (u >= 1) {
      return u - 0.5;
    }
    return u * u * u - u * u * u * u / 2;
  }

  /// Its mean share over the straight way from [from] to [to]: the edge's
  /// and the layer's, each averaged along it - exact when either is even
  /// along the way, as for a rain cell or a deep fog seen low.
  double meanShare(AirPoint from, AirPoint to) {
    final layer = meanLayer(from.height, to.height);
    if (everywhere) {
      return layer;
    }
    final u0 = _across(from);
    final u1 = _across(to);
    final double edge;
    if ((u1 - u0).abs() < 1e-6) {
      final u = u0.clamp(0.0, 1.0);
      edge = u * u * (3 - 2 * u);
    } else {
      edge = (_easedUpTo(u1) - _easedUpTo(u0)) / (u1 - u0);
    }
    return edge.clamp(0.0, 1.0) * layer;
  }

  /// Its mean share over a straight way from [h0] up or down to [h1].
  double meanLayer(double h0, double h1) {
    if ((h1 - h0).abs() < 1e-4) {
      return _layer(h0);
    }
    return (_layerUpTo(h1) - _layerUpTo(h0)) / (h1 - h0);
  }

  /// How much of it there is at [p], `0..1`.
  double shareAt(AirPoint p) {
    if (at == double.negativeInfinity) {
      return _layer(p.height);
    }
    final along =
        p.x * math.cos(angle) + p.ahead * math.sin(angle) - slant * p.height;
    final t = ((along - at) / math.max(widthM, 1e-6) + 0.5).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    return eased * _layer(p.height);
  }

  /// How deep it is to light straight up from the ground at [x], [ahead]
  /// inside it: what it takes of the sky's light (as a cloud's optical
  /// depth does).
  double verticalOpticalDepth(double x, double ahead) {
    // Its share along the ground, and its thickness: the layer's height
    // summed from the ground up, s ln(1 + e^(top / s)).
    final along = at == double.negativeInfinity
        ? 1.0
        : shareAt((x: x, ahead: ahead, height: 0)) / _layer(0);
    final s = math.max(topWidthM, 1e-3) / 4;
    final depth = s * math.log(1 + math.exp((topM / s).clamp(-60.0, 60.0)));
    return extinction * along * depth;
  }
}

/// The air of a scene as light crosses it: how much it takes away per metre
/// ([extinctionAt]) everywhere - clear air, rain and mist as [base], fog and
/// storm cells as [banks] - and so how much of a thing's light reaches the
/// eye across it ([transmittance]) and how far one sees ([visibilityAt]).
///
/// One field for everything the air does: the haze over far things, the
/// glow round lamps, the sun's light through a fog, and what a game asks of
/// the fog at a point. Parametric, so a shader works it out the same way.
@immutable
class AirField {
  const AirField({this.base = clearAir, this.banks = const []});

  /// Clear air's extinction, per metre: one sees some 20 km.
  static const double clearAir = 3.912 / 20000;

  /// At most this many banks; a shader takes this many.
  static const int maxBanks = 3;

  /// Per metre, what the air takes away everywhere.
  final double base;

  /// Fog and storm cells, at most [maxBanks].
  final List<AirBank> banks;

  /// Extinction for a visibility of [metres] (Koschmieder: 3.912 / V).
  static double ofVisibility(double metres) => 3.912 / math.max(metres, 1e-3);

  /// Per metre, what the air takes away at [p].
  double extinctionAt(AirPoint p) {
    var sigma = base;
    for (final bank in banks) {
      sigma += bank.extinction * bank.shareAt(p);
    }
    return sigma;
  }

  /// How far one sees at [p], m (Koschmieder).
  double visibilityAt(AirPoint p) => 3.912 / extinctionAt(p);

  /// The optical depth of the straight way from [from] to [to]: the
  /// extinction summed along it, in closed form ([AirBank.meanShare]).
  double opticalDepth(AirPoint from, AirPoint to) {
    final dx = to.x - from.x;
    final da = to.ahead - from.ahead;
    final dh = to.height - from.height;
    final length = math.sqrt(dx * dx + da * da + dh * dh);
    if (length <= 0) {
      return 0;
    }
    var tau = base * length;
    for (final bank in banks) {
      tau += bank.extinction * bank.meanShare(from, to) * length;
    }
    return tau;
  }

  /// The share of light that crosses from [from] to [to].
  double transmittance(AirPoint from, AirPoint to) =>
      math.exp(-opticalDepth(from, to));

  /// How deep the banks are to light straight up at [x], [ahead]: what they
  /// take of the sky's light and the sun's, as clouds do.
  double verticalOpticalDepth(double x, double ahead) {
    var sum = 0.0;
    for (final bank in banks) {
      sum += bank.verticalOpticalDepth(x, ahead);
    }
    return sum;
  }
}
