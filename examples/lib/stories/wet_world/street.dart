import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/flame_water.dart';

/// The line the street stands on, in the samples' 800x450 world.
const double groundLine = 330;

/// The sky at dusk, down to the ground line.
class Sky extends PositionComponent with Reflectable {
  Sky() : super(size: Vector2(800, groundLine));

  final Paint _paint = Paint()
    ..shader = Gradient.linear(Offset.zero, const Offset(0, groundLine), [
      const Color(0xFF26324A),
      const Color(0xFF6F7F9E),
    ]);

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// A row of house fronts against the sky, with a few lit windows. With
/// `lit` each lit window gives a little warm light, one of them flickering.
class Houses extends PositionComponent with Reflectable {
  Houses({bool lit = false})
    : super(position: Vector2(0, 170), size: Vector2(800, 160)) {
    if (!lit) {
      return;
    }
    const w = 800 / 7;
    for (var i = 0; i < _heights.length; i++) {
      for (var j = 0; j < 3; j++) {
        if ((i + j).isEven) {
          add(
            LightSource(
              position: Vector2(i * w + 25 + j * 28, size.y - _heights[i] + 31),
              radius: 46,
              intensity: 0.55,
              color: const Color(0xFFFFC870),
              flicker: i == 3 && j == 1 ? 0.6 : 0,
              sourceRadius: 2.5,
              seed: i * 3 + j,
            ),
          );
        }
      }
    }
  }

  static const _heights = [120.0, 150.0, 100.0, 140.0, 110.0, 160.0, 125.0];
  final Paint _wall = Paint()..color = const Color(0xFF1C2230);
  final Paint _window = Paint()..color = const Color(0xFFE8C77A);

  @override
  void render(Canvas canvas) {
    const w = 800 / 7;
    for (var i = 0; i < _heights.length; i++) {
      final h = _heights[i];
      final left = i * w;
      canvas.drawRect(Rect.fromLTWH(left + 4, size.y - h, w - 8, h), _wall);
      for (var j = 0; j < 3; j++) {
        if ((i + j).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(left + 18 + j * 28, size.y - h + 22, 14, 18),
            _window,
          );
        }
      }
    }
  }
}

/// A street lamp: a post and a warm bulb. In a reflection the bulb blurs into
/// a glow, as a light does in water. With `lit` it holds its lights: a cone
/// down onto the street and a small halo round the bulb.
class Lamp extends PositionComponent with Reflectable {
  Lamp({required double x, bool lit = false})
    : super(
        position: Vector2(x, groundLine),
        anchor: Anchor.bottomCenter,
        size: Vector2(20, 150),
        children: [
          if (lit) ...[
            LightSource(
              position: Vector2(10, 16),
              radius: 260,
              coneAngle: 1.9,
              intensity: 0.95,
              sourceRadius: 5,
            ),
            // The bulb's own glow; the air's halo round it is the cone's.
            LightSource(
              position: Vector2(10, 16),
              radius: 36,
              intensity: 0.9,
              sourceRadius: 0,
            ),
          ],
        ],
      );

  final Paint _post = Paint()..color = const Color(0xFF0E1118);
  final Paint _bulb = Paint()..color = const Color(0xFFFFE3A0);
  final Paint _glow = Paint()
    ..color = const Color(0x88FFD27A)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  @override
  void render(Canvas canvas) {
    canvas
      ..drawRect(Rect.fromLTWH(8, 12, 4, size.y - 12), _post)
      ..drawRect(const Rect.fromLTWH(0, 6, 20, 8), _post);
    final bulb = Offset(size.x / 2, 16);
    if (ReflectionPass.isActive) {
      canvas.drawCircle(bulb, 10, _glow);
    }
    canvas.drawCircle(bulb, 5, _bulb);
  }
}

/// A walker under an umbrella, going back and forth along the street.
class Walker extends PositionComponent with Reflectable {
  Walker({this.speed = 60})
    : super(
        position: Vector2(120, groundLine),
        anchor: Anchor.bottomCenter,
        size: Vector2(40, 90),
      );

  final double speed;
  double _direction = 1;
  double _time = 0;

  final Paint _body = Paint()..color = const Color(0xFF12151D);
  final Paint _canopy = Paint()..color = const Color(0xFF7A1F2B);

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    position.x += speed * _direction * dt;
    if (position.x > 700 || position.x < 100) {
      _direction = -_direction;
      position.x = position.x.clamp(100, 700);
    }
  }

  @override
  void render(Canvas canvas) {
    final stride = math.sin(_time * 6) * 6;
    canvas
      ..drawRect(const Rect.fromLTWH(14, 34, 12, 34), _body)
      ..drawCircle(const Offset(20, 28), 6, _body)
      ..drawRect(Rect.fromLTWH(15 + stride, 66, 4, 24), _body)
      ..drawRect(Rect.fromLTWH(21 - stride, 66, 4, 24), _body)
      ..drawRect(const Rect.fromLTWH(26, 8, 2, 40), _body)
      ..drawArc(
        const Rect.fromLTWH(0, 0, 54, 24),
        math.pi,
        math.pi,
        true,
        _canopy,
      );
  }
}

/// The road from the ground line down: dark asphalt, not a mirror itself.
class Road extends PositionComponent {
  Road() : super(position: Vector2(0, groundLine), size: Vector2(800, 120));

  final Paint _paint = Paint()..color = const Color(0xFF191C22);

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// The street without its water: sky, houses, a lamp, the walker, the road.
/// With [lit] the lamps and windows give light.
List<Component> street({bool lit = false}) => [
  Sky(),
  Houses(lit: lit),
  Lamp(x: 560, lit: lit),
  Lamp(x: 220, lit: lit),
  Road(),
  Walker(),
];

/// A film of water over the whole road: water like a puddle's, mirroring as
/// much, only lying rough on the asphalt - so everything it mirrors, the
/// street and the lamps alike, runs down it into a smear, and the rain keeps
/// it astir.
WaterSurface wetRoad({double reflectivity = 0.6, double chop = 4}) =>
    WaterSurface(
      position: Vector2(0, groundLine),
      size: Vector2(800, 120),
      shape: WaterShape.rect,
      waterLine: groundLine,
      color: const Color(0x00000000),
      reflectivity: reflectivity,
      squash: 0.6,
      fade: 0.9,
      tint: const Color(0x2219202A),
      // A film of water: drops break on it into small quick rings.
      depth: 0.1,
      rippleColor: const Color(0x88FFFFFF),
      // Rough asphalt under the water: everything it mirrors runs down it.
      streak: 45,
      // The rain keeps the whole film astir, breaking every streak into bands.
      chop: chop,
    );

/// A puddle lying on the road in front of the walker: its water line is the
/// line the street stands on, so feet meet their reflection. It shows the same
/// reflection as the wet road around it - how squeezed a reflection is
/// depends on how far off the water lies, not on how deep it is - only
/// brighter and clearer.
WaterSurface puddle({
  required double left,
  required double width,
  double top = 345,
  double height = 34,
  double reflectivity = 0.75,
  double squash = 0.6,
  double fade = 0.7,
  double chop = 1.2,
}) => WaterSurface(
  position: Vector2(left, top),
  size: Vector2(width, height),
  waterLine: groundLine,
  color: const Color(0x66151A22),
  reflectivity: reflectivity,
  squash: squash,
  fade: fade,
  tint: const Color(0x2230405A),
  // Water to spare (depth 1, the default): drops set off wide slow rings.
  rippleColor: const Color(0x66FFFFFF),
  // Still water: nearly a clear mirror.
  streak: 6,
  chop: chop,
);

/// Where a drop lands: in the first puddle that covers the spot, else on the
/// wet [road], where it makes a weaker ring.
void landOn(
  List<WaterSurface> puddles,
  WaterSurface? road,
  Vector2 at,
  double strength,
) {
  for (final p in puddles) {
    if (p.covers(at)) {
      p.splash(at, strength: strength);
      return;
    }
  }
  road?.splash(at, strength: strength * 0.7);
}
