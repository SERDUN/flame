import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// A light in the world: a lamp, a lit window, a headlight.
///
/// It shines from its position out to [radius], fading with distance, all
/// around or - with a [coneAngle] - in a cone along [coneDirection] (a
/// street lamp shines down). It draws nothing itself: a `Lighting` layer
/// cuts it out of the night and adds its glow.
class LightSource extends PositionComponent {
  LightSource({
    super.position,
    this.color = const Color(0xFFFFD9A0),
    this.intensity = 1,
    this.radius = 120,
    this.coneAngle,
    this.coneDirection = math.pi / 2,
    this.flicker = 0,
    this.sourceRadius = 6,
    int seed = 0,
  }) : _phase = seed * 1.618;

  /// The light's colour.
  Color color;

  /// How bright it is: 1 fully lifts the night at its centre.
  double intensity;

  /// How far it reaches, world units.
  double radius;

  /// Full angle of the cone, radians; `null` shines all around.
  double? coneAngle;

  /// The cone's axis, radians from +x (y down, so pi / 2 is straight down).
  double coneDirection;

  /// How much it flickers, `0..1`: a failing tube, a candle.
  double flicker;

  /// Radius of what glows itself - a bulb, a tube - world units. Water
  /// mirrors this as a bright spot, not only the light it casts.
  double sourceRadius;

  /// Share of the cone, on each side, over which the light eases to
  /// nothing at its edge, `0..1`.
  static const double softEdge = 0.65;

  final double _phase;
  double _time = 0;

  /// Its brightness now, flicker included.
  double get strength {
    if (flicker <= 0) {
      return intensity;
    }
    final t = _time * 9 + _phase;
    final wobble = 0.5 + 0.25 * math.sin(t) + 0.25 * math.sin(t * 2.7 + 1.3);
    return intensity * (1 - flicker * wobble);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  /// How much of this light reaches [point] (world coordinates), `0..1` times
  /// [strength]: a smooth fall to nothing at [radius], and nothing outside
  /// the cone.
  double lightAt(Vector2 point) {
    final origin = absolutePosition;
    final dx = point.x - origin.x;
    final dy = point.y - origin.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance >= radius) {
      return 0;
    }
    final falloff = math.pow(1 - distance / radius, 2).toDouble();
    return strength * falloff * _coneFactor(dx, dy, distance);
  }

  double _coneFactor(double dx, double dy, double distance) {
    final cone = coneAngle;
    if (cone == null || distance < 1e-6) {
      return 1;
    }
    var off = (math.atan2(dy, dx) - coneDirection).abs() % (2 * math.pi);
    if (off > math.pi) {
      off = 2 * math.pi - off;
    }
    final half = cone / 2;
    // Full along the middle, easing to nothing over the outer part on each
    // side - light has no edge, as the lighting draws it.
    final edge = half * softEdge;
    if (off <= half - edge) {
      return 1;
    }
    if (off >= half) {
      return 0;
    }
    final t = (half - off) / edge;
    return t * t * (3 - 2 * t);
  }

  /// The area the light covers, world coordinates: a disc, or the cone's
  /// wedge.
  Path shape() {
    final origin = absolutePosition.toOffset();
    final cone = coneAngle;
    if (cone == null) {
      return Path()..addOval(Rect.fromCircle(center: origin, radius: radius));
    }
    return Path()
      ..moveTo(origin.dx, origin.dy)
      ..arcTo(
        Rect.fromCircle(center: origin, radius: radius),
        coneDirection - cone / 2,
        cone,
        false,
      )
      ..close();
  }
}
