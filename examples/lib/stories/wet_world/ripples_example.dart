import 'package:examples/stories/wet_world/rain.dart';
import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_water/flame_water.dart';

class RipplesExample extends FlameGame with TapCallbacks {
  RipplesExample({this.dropsPerSec = 250})
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
