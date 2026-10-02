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
/// drops). Up from the ground it thins as exp(-h / [scaleHeightM]): a ground
/// fog a metre or two, a deep fog tens of metres.
@immutable
class AirBank {
  const AirBank({
    required this.extinction,
    this.at = double.negativeInfinity,
    this.angle = 0,
    this.widthM = 20,
    this.slant = 0,
    this.scaleHeightM = 50,
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

  /// How high it reaches: it thins to 1/e every this many metres up.
  final double scaleHeightM;

  /// How much of it there is at [p], `0..1`.
  double shareAt(AirPoint p) {
    if (at == double.negativeInfinity) {
      return math.exp(-math.max(p.height, 0) / scaleHeightM);
    }
    final along =
        p.x * math.cos(angle) + p.ahead * math.sin(angle) - slant * p.height;
    final t = ((along - at) / math.max(widthM, 1e-6) + 0.5).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    return eased * math.exp(-math.max(p.height, 0) / scaleHeightM);
  }

  /// How deep it is to light straight up from the ground at [x], [ahead]
  /// inside it: what it takes of the sky's light (as a cloud's optical
  /// depth does).
  double verticalOpticalDepth(double x, double ahead) {
    final share = shareAt((x: x, ahead: ahead, height: 0));
    return extinction * share * scaleHeightM;
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

  /// Steps the way from one point to another is cut into: a bank's edge is
  /// some metres wide, and the way tens of metres long.
  static const int steps = 24;

  /// The optical depth of the straight way from [from] to [to]: the
  /// extinction summed along it (midpoints of [steps] equal parts).
  double opticalDepth(AirPoint from, AirPoint to) {
    final dx = to.x - from.x;
    final da = to.ahead - from.ahead;
    final dh = to.height - from.height;
    final length = math.sqrt(dx * dx + da * da + dh * dh);
    if (length <= 0) {
      return 0;
    }
    if (banks.isEmpty) {
      return base * length;
    }
    var sum = 0.0;
    for (var i = 0; i < steps; i++) {
      final t = (i + 0.5) / steps;
      sum += extinctionAt((
        x: from.x + dx * t,
        ahead: from.ahead + da * t,
        height: from.height + dh * t,
      ));
    }
    return sum / steps * length;
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
