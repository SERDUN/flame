import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_water/flame_water.dart';

class MirrorPuddleExample extends FlameGame {
  MirrorPuddleExample({
    this.reflectivity = 0.75,
    this.squash = 1,
    this.fade = 0.7,
    this.wetRoadOn = true,
  }) : super(
         camera: CameraComponent.withFixedResolution(width: 800, height: 450),
       );

  static const String description = '''
    A puddle mirrors the street above it: the sky, the houses, the lamps and
    the walker, clipped to its shape, squeezed as water seen at a low angle
    and faded with depth. The road itself is a thin film of water with a
    faint mirror of its own. Nothing is rendered off screen: each reflected
    component is drawn a second time, upside down.
  ''';

  final double reflectivity;
  final double squash;
  final double fade;
  final bool wetRoadOn;

  @override
  Future<void> onLoad() async {
    await WaterShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    await world.addAll([
      ...street(),
      if (wetRoadOn) wetRoad(),
      puddle(
        left: 260,
        width: 320,
        reflectivity: reflectivity,
        fade: fade,
      )..squash = squash,
      puddle(left: 500, width: 130, top: 398, height: 44),
      Rain(),
    ]);
  }
}
