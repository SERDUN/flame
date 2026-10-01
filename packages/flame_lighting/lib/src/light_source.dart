import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/light_mirror.dart';
import 'package:flame_lighting/src/lighting.dart';

/// A light in the world: a lamp, a lit window, a headlight.
///
/// It shines from its position out to [radius], fading with distance, all
/// around or - with a [coneAngle] - in a cone along [coneDirection] (a
/// street lamp shines down). A `Lighting` layer cuts it out of the night and
/// adds its glow; as an [Emissive] it draws its own source - a disc
/// [sourceRadius] across - and the halo the air's haze makes round it, which
/// water then mirrors like anything else.
class LightSource extends PositionComponent with Emissive {
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
  /// the cone. A point [inFront] world units nearer the eye than the light
  /// (rain between it and the eye) is that much farther from it.
  double lightAt(Vector2 point, {double inFront = 0}) {
    final origin = absolutePosition;
    final dx = point.x - origin.x;
    final dy = point.y - origin.y;
    final distance = math.sqrt(dx * dx + dy * dy + inFront * inFront);
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

  final Paint _glow = Paint();

  /// World y of the ground it stands on, if not the line water mirrors
  /// about (see [Emissive.standsAt]).
  @override
  double? standsAt;

  /// Radius of the halo [haze] makes round the source.
  double haloRadius(double haze) => sourceRadius * (6 + 24 * haze);

  /// The source and its halo, drawn in place: whatever stands in front of
  /// the light hides them.
  @override
  void render(Canvas canvas) => renderEmissive(canvas);

  @override
  void renderEmissive(Canvas canvas) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0 || sourceRadius <= 0) {
      return;
    }
    final haze = (Lighting.current ?? Lighting.of(this))?.haze ?? 0;
    if (haze > 0) {
      // Wet air scatters the light into a wide soft halo round the source.
      // Scattered light, as bright as it is even in a mirror that brings
      // the source back brighter than white.
      final a = haze * s * 0.6 / Lighting.headroom;
      final halo = haloRadius(haze);
      _glow.shader = Gradient.radial(
        Offset.zero,
        halo,
        [
          color.withValues(alpha: a),
          color.withValues(alpha: a * 0.35),
          color.withValues(alpha: 0),
        ],
        const [0, 0.25, 1],
      );
      canvas.drawCircle(Offset.zero, halo, _glow);
    }
    // The source itself: nearly white at its heart.
    _glow.shader = Gradient.radial(
      Offset.zero,
      sourceRadius * 1.6,
      [
        Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!.withValues(alpha: s),
        color.withValues(alpha: s),
        color.withValues(alpha: 0),
      ],
      const [0, 0.55, 1],
    );
    canvas.drawCircle(Offset.zero, sourceRadius * 1.6, _glow);
  }
}
