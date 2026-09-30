import 'package:examples/stories/wet_world/rain.dart';
import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/flame_water.dart';

class RainyNightExample extends FlameGame {
  RainyNightExample({
    this.darkness = 0.7,
    this.glow = 0.35,
    this.haze = 0.5,
    this.dropsPerSec = 250,
  }) : super(
         camera: CameraComponent.withFixedResolution(width: 800, height: 450),
       );

  static const String description = '''
    Everything at once, at night: lamps light soft cones of the street, the
    wet air scatters them into halos and the lit windows glow; the wet road
    breaks every lamp's reflection into a shimmering column of slivers and
    the puddles mirror the lamp itself as a bright spot; rain shines in the lamps' light and
    all but vanishes between them; every drop ripples the water it lands in,
    bending what the water shows.
  ''';

  final double darkness;
  final double glow;
  final double haze;
  final double dropsPerSec;

  @override
  Future<void> onLoad() async {
    await WaterShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    final road = wetRoad();
    final puddles = [
      puddle(left: 260, width: 320),
      puddle(left: 90, width: 110, top: 395, height: 26),
    ];
    final lighting = Lighting(darkness: darkness, glow: glow, haze: haze);
    await world.addAll([
      ...street(lit: true),
      road,
      ...puddles,
      lighting,
      Rain(
        dropsPerSec: dropsPerSec,
        onLand: (at, strength) => landOn(puddles, road, at, strength),
        lighting: lighting,
        priority: 1100,
      ),
    ]);
  }
}
