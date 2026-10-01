import 'dart:ui';

import 'package:examples/stories/wet_world/street.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/flame_water.dart';

class RainyNightExample extends FlameGame {
  RainyNightExample({
    this.skyLight = 0.15,
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
    the sky. Everything that happens between them is their own: the rain
    falls on whatever catches it, the water ripples and bends what it
    mirrors, the houses get wet and glint, the lights light the street, lay
    pools on the road and show in the water. Raise the sky's light and the
    same street comes into the day: the eye adapts, and the lamps fade
    against the sky. Stop the rain and the street
    dries as fast as the weather dries it: the walls first, then the
    asphalt, the puddles last.
  ''';

  /// How much light the sky gives (lights' units): 0.15 a cloudy night
  /// over a town, 40 noon.
  final double skyLight;
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
    required double skyLight,
    required double glow,
    required double haze,
    required double rain,
    required double drying,
  }) {
    _lighting
      ?..skyLight = skyLight
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
    await LightShader.load();
    camera.viewfinder.anchor = Anchor.topLeft;
    world.addAll([
      ...street(lit: true),
      wetRoad(),
      puddle(left: 260, width: 320),
      puddle(left: 500, width: 130, top: 398, height: 44),
      _lighting = Lighting(
        // A cloudy night's light, a little blue.
        sky: const Color(0xFFB4C4FF),
        skyLight: skyLight,
        glow: glow,
        haze: haze,
      ),
      _rain = Rain(intensity: rain, drying: drying),
    ]);
    setWetness(wetness);
  }
}
