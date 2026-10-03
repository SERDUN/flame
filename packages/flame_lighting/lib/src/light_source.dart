import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';

/// A light in the world as a component: a lamp's bulb, a lit window, a neon
/// tube, a headlight - any [Light], where this component is.
///
/// It carries its [light] onto the stage (so the lighting cuts it out of the
/// night, rain shines in it, water mirrors it) and draws what glows itself
/// in place: a bulb's disc, a window's pane, a tube - with the halo the air's
/// haze makes round it. Whatever stands in front of it hides them.
///
/// Any other component can carry lights too ([LightCarrier]); this is the
/// one that also draws them.
class LightSource extends PositionComponent with OnStage, LightCarrier {
  /// A bulb, or with [coneAngle] a cone along [coneDirection] (y down, so
  /// pi / 2 is straight down) whose bulb throws [spill] of its light all
  /// round within [spillRadius] - a street lamp lighting its own head.
  LightSource({
    super.position,
    Color color = const Color(0xFFFFD9A0),
    double intensity = 1,
    double radius = 120,
    double? coneAngle,
    double coneDirection = math.pi / 2,
    double flicker = 0,
    double sourceRadius = 6,
    double depth = 0,
    Falloff falloff = Falloff.smooth,
    double? switchOnBelow,
    int seed = 0,
    double spill = 0,
    double spillRadius = 0,
  }) : light = coneAngle == null
           ? Light.point(
               color: color,
               intensity: intensity,
               radius: radius,
               flicker: flicker,
               sourceRadius: sourceRadius,
               depth: depth,
               falloff: falloff,
               switchOnBelow: switchOnBelow,
               seed: seed,
             )
           : Light.cone(
               color: color,
               intensity: intensity,
               radius: radius,
               spread: coneAngle,
               direction: coneDirection,
               flicker: flicker,
               sourceRadius: sourceRadius,
               depth: depth,
               falloff: falloff,
               switchOnBelow: switchOnBelow,
               seed: seed,
               spill: spill,
               spillRadius: spillRadius,
             );

  /// Any [light], at [position].
  LightSource.of(this.light, {super.position});

  /// The light it gives.
  final Light light;

  @override
  Iterable<Light> get lights => [light];

  final Paint _glow = Paint();

  /// The halo the haze makes round a source at [center], [radius] wide, in
  /// [color] at [alpha]: one profile for the halo a light draws and the
  /// one the lighting cuts out of the night, which must match or a ring
  /// shows round each.
  static Gradient halo(
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) => Gradient.radial(
    center,
    radius,
    [
      color.withValues(alpha: alpha),
      color.withValues(alpha: alpha * 0.35),
      color.withValues(alpha: 0),
    ],
    const [0, 0.25, 1],
  );

  /// How bright it is now.
  double get strength {
    final frame = stage?.frame;
    return light.strengthAt(frame?.time ?? 0, frame?.light.sensorLevel ?? 1);
  }

  @override
  void render(Canvas canvas) {
    final s = strength;
    if (s <= 0) {
      return;
    }
    final haze = stage?.frame.light.haze ?? 0;
    // The source shows as bright as it is drawn; the halo the wet air makes
    // round it is its light scattered toward the eye, a share of it - never
    // brighter than the source, whatever the eye's exposure.
    final glow = s.clamp(0.0, 1.0);
    final at = light.offset.toOffset();
    switch (light.shape) {
      case LightShape.point:
      case LightShape.cone:
        _bulb(canvas, at, glow, haze);
      case LightShape.area:
        _pane(canvas, at, glow, haze);
      case LightShape.line:
        _tube(canvas, at, glow, haze);
      case LightShape.directional:
        break;
    }
  }

  void _bulb(Canvas canvas, Offset at, double s, double haze) {
    final r = light.sourceRadius;
    if (r <= 0) {
      return;
    }
    if (haze > 0) {
      // Wet air scatters the light into a wide soft halo round the source.
      final halo = r * (6 + 24 * haze);
      _glow.shader = LightSource.halo(
        at,
        halo,
        light.color,
        haze * s * 0.6,
      );
      canvas.drawCircle(at, halo, _glow);
    }
    // The source itself: nearly white at its heart.
    _glow.shader = Gradient.radial(
      at,
      r * 1.6,
      [
        Color.lerp(light.color, const Color(0xFFFFFFFF), 0.6)!.withValues(
          alpha: s,
        ),
        light.color.withValues(alpha: s),
        light.color.withValues(alpha: 0),
      ],
      const [0, 0.55, 1],
    );
    canvas.drawCircle(at, r * 1.6, _glow);
  }

  void _pane(Canvas canvas, Offset at, double s, double haze) {
    final rect = Rect.fromCenter(
      center: at,
      width: light.extent.x,
      height: light.extent.y,
    );
    if (haze > 0) {
      // The air before a lit window glows a little past its frame: a few
      // fainter frames out, not a blur - blurs in a picture that a mirror
      // snapshots exhaust Impeller Metal's command queue.
      final spill = math.min(rect.width, rect.height) * (0.3 + 1.2 * haze);
      _glow.shader = null;
      for (var k = 3; k >= 1; k--) {
        _glow.color = light.color.withValues(alpha: haze * s * 0.08);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(spill * k / 3),
            Radius.circular(spill * k / 3),
          ),
          _glow,
        );
      }
    }
    _glow
      ..shader = null
      ..color = Color.lerp(
        light.color,
        const Color(0xFFFFFFFF),
        0.25,
      )!.withValues(alpha: s);
    canvas.drawRect(rect, _glow);
  }

  void _tube(Canvas canvas, Offset at, double s, double haze) {
    final half = light.extent.x / 2;
    final dir = Offset(math.cos(light.direction), math.sin(light.direction));
    final a = at - dir * half;
    final b = at + dir * half;
    final width = math.max(light.sourceRadius, light.extent.x * 0.02);
    if (haze > 0) {
      // Wider, fainter strokes round the tube: its glow in the wet air.
      _glow
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var k = 3; k >= 1; k--) {
        _glow
          ..strokeWidth = width * (1 + (2 + 8 * haze) * k / 3)
          ..color = light.color.withValues(alpha: haze * s * 0.1);
        canvas.drawLine(a, b, _glow);
      }
    }
    _glow
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = Color.lerp(
        light.color,
        const Color(0xFFFFFFFF),
        0.5,
      )!.withValues(alpha: s);
    canvas.drawLine(a, b, _glow);
    _glow.style = PaintingStyle.fill;
  }
}
