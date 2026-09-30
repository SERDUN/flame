import 'dart:math' as math;
import 'dart:ui';

import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame_water/flame_water.dart';

/// Rain over the street, seen from the side.
///
/// Every drop lands at its own depth on the road: a far one near the line the
/// street stands on, a near one low on the screen. So that the eye can tell
/// which puddle a drop is falling into, depth shows in the drop: a near drop
/// is longer, brighter, thicker and crosses the screen faster than a far one.
/// Where it lands it bursts into a few droplets at once, and [onLand] is told
/// in that same step - a ring in a puddle starts exactly where and when the
/// drop hits.
class Rain extends Component with Reflectable {
  Rain({required this.dropsPerSec, required this.onLand});

  final double dropsPerSec;
  final void Function(Vector2 at, double strength) onLand;

  /// Depth of the road the drops land on, below [groundLine].
  static const double _road = 110;
  static const double _wind = 80;

  final math.Random _random = math.Random(7);
  final List<_Drop> _drops = [];
  final List<_Droplet> _droplets = [];
  double _due = 0;
  final Paint _streak = Paint()..strokeCap = StrokeCap.round;
  final Paint _splash = Paint()
    ..color = const Color(0xFFDCE6F2)
    ..strokeCap = StrokeCap.round;

  @override
  void onMount() {
    super.onMount();
    // The rain is already falling when the scene opens.
    final inAir = (dropsPerSec * 0.6).round();
    for (var i = 0; i < inAir; i++) {
      final drop = _newDrop(0);
      drop.at.y = _random.nextDouble() * drop.land;
      _drops.add(drop);
    }
  }

  _Drop _newDrop(double lead) {
    final depth = _random.nextDouble();
    final speed = 520 + 380 * depth;
    return _Drop(
      at: Vector2(
        -40 + _random.nextDouble() * 880,
        // Spread over the way it falls in this step: drops born in one step
        // at one height would fall as a line.
        -30 - _random.nextDouble() * speed * lead,
      ),
      land: groundLine + 4 + depth * _road,
      depth: depth,
      speed: speed,
      strength: 0.4 + 0.6 * _random.nextDouble(),
    );
  }

  @override
  void update(double dt) {
    _due += dt * dropsPerSec;
    while (_due >= 1) {
      _due -= 1;
      _drops.add(_newDrop(dt));
    }
    for (final d in _drops) {
      d.at
        ..y += d.speed * dt
        ..x += _wind * dt;
    }
    _drops.removeWhere((d) {
      if (d.at.y < d.land) {
        return false;
      }
      final at = Vector2(d.at.x, d.land);
      _burst(at, d);
      onLand(at, d.strength);
      return true;
    });
    for (final p in _droplets) {
      p.age += dt;
      p.velocity.y += 900 * dt;
      p.at.addScaled(p.velocity, dt);
    }
    _droplets.removeWhere((p) => p.age >= p.life || p.at.y > p.floor);
  }

  /// A drop bursting where it lands: a few droplets thrown up and out, higher
  /// for a near, heavy drop.
  void _burst(Vector2 at, _Drop d) {
    final size = (0.5 + 0.5 * d.depth) * d.strength;
    final count = 2 + (size * 3).round();
    for (var i = 0; i < count; i++) {
      final side = _random.nextBool() ? 1 : -1;
      _droplets.add(
        _Droplet(
          at: at.clone(),
          velocity: Vector2(
            side * (20 + 70 * _random.nextDouble()) * size,
            -(90 + 120 * _random.nextDouble()) * size,
          ),
          floor: at.y + 1,
          life: 0.35,
          width: 1 + 1.5 * d.depth,
        ),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    for (final d in _drops) {
      final length = (12 + 30 * d.depth) * d.strength;
      _streak
        ..color = Color.fromRGBO(214, 224, 238, 0.3 + 0.6 * d.depth)
        ..strokeWidth = 0.8 + 1.4 * d.depth;
      final head = Offset(d.at.x, math.min(d.at.y, d.land));
      canvas.drawLine(
        head.translate(-length * _wind / d.speed, -length),
        head,
        _streak,
      );
    }
    for (final p in _droplets) {
      _splash.strokeWidth = p.width;
      canvas.drawPoints(PointMode.points, [p.at.toOffset()], _splash);
    }
  }
}

class _Drop {
  _Drop({
    required this.at,
    required this.land,
    required this.depth,
    required this.speed,
    required this.strength,
  });

  final Vector2 at;

  /// Screen y where it hits the road, at its depth.
  final double land;

  /// 0 far (lands at the line the street stands on) .. 1 near.
  final double depth;
  final double speed;
  final double strength;
}

class _Droplet {
  _Droplet({
    required this.at,
    required this.velocity,
    required this.floor,
    required this.life,
    required this.width,
  });

  final Vector2 at;
  final Vector2 velocity;

  /// It falls back to the road here and is gone.
  final double floor;
  final double life;
  final double width;
  double age = 0;
}
