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
    Rain on the street: every drop lands somewhere on the road, and where it
    lands the water ripples - a ring in a puddle, a small quick one in the film
    on the road - and the ring bends the reflection around it, through the
    water shader. Tap a puddle to splash it yourself.
  ''';

  final double dropsPerSec;
  final List<WaterSurface> _puddles = [];
  final WaterSurface _road = wetRoad();

  @override
  Future<void> onLoad() async {
    await WaterShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    _puddles.addAll([
      puddle(left: 260, width: 320),
      puddle(left: 500, width: 130, top: 398, height: 44),
    ]);
    await world.addAll([
      ...street(),
      _road,
      ..._puddles,
      Rain(dropsPerSec: dropsPerSec, onLand: _land),
    ]);
  }

  void _land(Vector2 at, double strength) =>
      landOn(_puddles, _road, at, strength);

  @override
  void onTapDown(TapDownEvent event) {
    _land(camera.globalToLocal(event.canvasPosition), 1);
  }
}
