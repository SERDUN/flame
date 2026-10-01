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
    this.rain = 1,
    this.drying = 1,
    this.wetness = 1,
  }) : super(
         camera: CameraComponent.withFixedResolution(width: 800, height: 450),
       );

  static const String description = '''
    A street at night in the rain, made only of elements - the road, its
    film of water, puddles, houses, lamps, a walker with a torch, the rain,
    the night. Everything that happens between them is their own: the rain
    falls on whatever catches it, the water ripples and bends what it
    mirrors, the houses get wet and glint, the lights cut the night, lay
    pools on the road and show in the water. Stop the rain and the street
    dries as fast as the weather dries it: the walls first, then the
    asphalt, the puddles last.
  ''';

  final double darkness;
  final double glow;
  final double haze;
  final double rain;
  final double drying;

  /// How wet the street is when the scene opens, from dry to soaked; from
  /// then on the rain and the drying move it.
  final double wetness;

  Lighting? _lighting;
  Rain? _rain;

  /// Changes the weather on the running street, keeping how wet it has got.
  void setWeather({
    required double darkness,
    required double glow,
    required double haze,
    required double rain,
    required double drying,
  }) {
    _lighting
      ?..darkness = darkness
      ..glow = glow
      ..haze = haze;
    _rain
      ?..intensity = rain
      ..drying = drying;
  }

  /// Makes everything that gets wet [wetness] wet now.
  void setWetness(double wetness) {
    for (final wet in world.descendants().whereType<Wettable>()) {
      wet.wetness = wetness;
    }
  }

  @override
  Future<void> onLoad() async {
    await WaterShader.load();
    await LightingShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    await world.addAll([
      ...street(lit: true),
      wetRoad(),
      puddle(left: 260, width: 320),
      puddle(left: 500, width: 130, top: 398, height: 44),
      _lighting = Lighting(darkness: darkness, glow: glow, haze: haze),
      _rain = Rain(intensity: rain, drying: drying),
    ]);
    setWetness(wetness);
  }
}
