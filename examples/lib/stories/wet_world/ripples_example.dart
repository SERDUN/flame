import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_water/flame_water.dart';

class RipplesExample extends FlameGame with TapCallbacks {
  RipplesExample({this.rain = 1})
    : super(
        camera: CameraComponent.withFixedResolution(width: 800, height: 450),
      );

  static const String description = '''
    Rain on the street by day: every drop lands on whatever catches it - a
    ring in a puddle, a small quick one in the film on the road, a splash on
    a roof - and the ring bends the reflection around it, through the water
    shader. Tap a puddle to splash it yourself.
  ''';

  final double rain;
  final List<WaterSurface> _puddles = [];

  @override
  Future<void> onLoad() async {
    await WaterShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    _puddles.addAll([
      puddle(left: 260, width: 320),
      puddle(left: 500, width: 130, top: 398, height: 44),
    ]);
    world.addAll([
      ...street(),
      wetRoad(),
      ..._puddles,
      Rain(intensity: rain),
    ]);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final at = camera.globalToLocal(event.canvasPosition);
    for (final puddle in _puddles) {
      if (puddle.covers(at)) {
        puddle.splash(at);
      }
    }
  }
}
