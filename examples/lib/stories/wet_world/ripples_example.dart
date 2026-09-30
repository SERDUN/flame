import 'dart:math' as math;
import 'dart:ui';

import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_water/flame_water.dart';

class RipplesExample extends FlameGame with TapCallbacks {
  RipplesExample({this.dropsPerSec = 60})
    : super(
        camera: CameraComponent.withFixedResolution(width: 800, height: 450),
      );

  static const String description = '''
    Rain on the street: every drop lands somewhere on the road, and one that
    lands in a puddle starts a ring there - a heavy drop a bigger, brighter
    one. Tap a puddle to splash it yourself.
  ''';

  final double dropsPerSec;
  final List<WaterSurface> _water = [];

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    _water.addAll([
      puddle(left: 260, width: 320),
      puddle(left: 90, width: 110, top: 395, height: 26),
    ]);
    await world.addAll([
      ...street(),
      wetRoad(),
      ..._water,
      Rain(dropsPerSec: dropsPerSec, onLand: _land),
    ]);
  }

  void _land(Vector2 at, double strength) {
    for (final water in _water) {
      if (water.covers(at)) {
        water.splash(at, strength: strength);
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    _land(camera.globalToLocal(event.canvasPosition), 1);
  }
}

/// Streaks falling to the road; each lands at its own depth on it (nearer
/// ones lower on screen) and reports where.
class Rain extends Component with Reflectable {
  Rain({required this.dropsPerSec, required this.onLand});

  final double dropsPerSec;
  final void Function(Vector2 at, double strength) onLand;

  final math.Random _random = math.Random(7);
  final List<_Drop> _drops = [];
  double _due = 0;
  final Paint _paint = Paint()
    ..color = const Color(0x99C8D4E6)
    ..strokeWidth = 1.2;

  @override
  void update(double dt) {
    _due += dt * dropsPerSec;
    while (_due >= 1) {
      _due -= 1;
      final land = groundLine + 6 + _random.nextDouble() * 110;
      _drops.add(
        _Drop(
          Vector2(_random.nextDouble() * 800, -20),
          land,
          0.3 + 0.7 * _random.nextDouble(),
        ),
      );
    }
    for (final drop in _drops) {
      drop.at.y += 700 * dt;
    }
    _drops.removeWhere((d) {
      if (d.at.y < d.land) {
        return false;
      }
      onLand(Vector2(d.at.x, d.land), d.strength);
      return true;
    });
  }

  @override
  void render(Canvas canvas) {
    for (final d in _drops) {
      canvas.drawLine(
        Offset(d.at.x, d.at.y - 14 * d.strength),
        Offset(d.at.x, d.at.y),
        _paint,
      );
    }
  }
}

class _Drop {
  _Drop(this.at, this.land, this.strength);

  final Vector2 at;
  final double land;
  final double strength;
}
