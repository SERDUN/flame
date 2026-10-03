import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brightness (red channel) of the rendered game at a pixel.
Future<int Function(int x, int y)> _render(FlameGame game) async {
  // The stage makes the frame's light.
  game.update(0);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 800 + x) * 4);
}

/// The ground from y 400 down.
class _Road extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 200);
}

/// A lamp at (400, 300) over water from the line 400 down, in a black night;
/// or [light] instead of the lamp.
Future<WaterSurface> _scene(
  FlameGame game, {
  double streak = 0,
  Component? light,
  bool road = false,
}) async {
  await WaterShader.load(asset: 'shaders/water.frag');
  game.camera.viewfinder.anchor = Anchor.topLeft;
  final water = WaterSurface(
    position: Vector2(0, 400),
    size: Vector2(800, 200),
    shape: WaterShape.rect,
    color: const Color(0xFF000000),
    fade: 0,
    streak: streak,
    waveAmplitude: 6,
  );
  game.world.addAll([
    if (road) _Road(),
    water,
    light ?? LightSource(position: Vector2(400, 300), radius: 60),
    Lighting(skyLight: 0, glow: 0, haze: 0),
  ]);
  await game.ready();
  return water;
}

void main() {
  testWithFlameGame('still water mirrors a lamp as a lamp', (game) async {
    await _scene(game);
    final at = await _render(game);
    expect(at(400, 500), greaterThan(200), reason: 'the lamp mirrored');
    expect(at(400, 540), lessThan(20), reason: 'not smeared on still water');
  });

  testWithFlameGame(
    'the mirrored lamp is never brighter or bigger than the lamp',
    (game) async {
      // A strong lamp in a black night, the eye adapted to the dark: its light
      // is exposed far past white, its source is drawn no brighter than white.
      await _scene(
        game,
        light: LightSource(
          position: Vector2(400, 300),
          radius: 60,
          intensity: 6,
          sourceRadius: 12,
        ),
      );
      final at = await _render(game);
      var lamp = 0;
      var lampLit = 0;
      for (var y = 270; y < 330; y++) {
        for (var x = 370; x < 430; x++) {
          lamp = at(x, y) > lamp ? at(x, y) : lamp;
          if (at(x, y) > 200) {
            lampLit++;
          }
        }
      }
      var mirror = 0;
      var mirrorLit = 0;
      for (var y = 401; y < 600; y++) {
        for (var x = 340; x < 460; x++) {
          mirror = at(x, y) > mirror ? at(x, y) : mirror;
          if (at(x, y) > 200) {
            mirrorLit++;
          }
        }
      }
      expect(mirror, greaterThan(40), reason: 'it is mirrored');
      expect(mirror, lessThanOrEqualTo(lamp));
      expect(mirrorLit, lessThanOrEqualTo(lampLit));
    },
  );

  testWithFlameGame('a drop by the mirrored lamp bends it', (game) async {
    final water = await _scene(game);
    final before = await _render(game);
    water
      ..splash(Vector2(412, 500))
      ..update(0.1);
    final after = await _render(game);
    var changed = 0;
    for (var x = 390; x < 411; x++) {
      if ((before(x, 500) - after(x, 500)).abs() > 40) {
        changed++;
      }
    }
    expect(changed, greaterThan(2));
  });

  testWithFlameGame('a rough surface smears the lamp down into a streak', (
    game,
  ) async {
    await _scene(game, streak: 80);
    final at = await _render(game);
    // Still water shows nothing 40 below the mirrored lamp (tested above);
    // a rough surface carries its light there, in a narrow column that
    // fades smoothly - one continuous smear, no copies of the lamp in it.
    expect(at(400, 540), greaterThan(15), reason: 'the streak below it');
    expect(at(430, 540), lessThan(at(400, 540)), reason: 'narrow');
    final column = [for (var y = 505; y < 560; y++) at(400, y)];
    for (var i = 1; i < column.length; i++) {
      expect(
        column[i],
        lessThanOrEqualTo(column[i - 1] + 2),
        reason: '$column',
      );
    }
  });

  testWithFlameGame('a lit window is mirrored whole, not as a point', (
    game,
  ) async {
    await _scene(
      game,
      light: LightSource.of(
        Light.area(size: Vector2(160, 40), radius: 60),
        position: Vector2(400, 340),
      ),
    );
    final at = await _render(game);
    // Mirrored about the line at 400: from 440 to 480, x 320 to 480.
    expect(at(400, 460), greaterThan(200));
    expect(at(470, 460), greaterThan(200), reason: 'its corner as bright');
    expect(at(540, 460), lessThan(20), reason: 'nothing past its frame');
  });

  testWithFlameGame('a lamp nearer the eye is mirrored about where it stands', (
    game,
  ) async {
    await _scene(
      game,
      road: true,
      // At depth 0.5 it stands at y 500, its bulb 50 above that: its
      // reflection 50 below it, at 550 - not about the street line.
      light: LightSource(position: Vector2(400, 450), radius: 60, depth: 0.5),
    );
    final at = await _render(game);
    // Seen from above there, water mirrors little of it (Fresnel), but the
    // brightest spot is there.
    expect(at(400, 550), greaterThan(30));
    expect(at(400, 525), lessThan(at(400, 550) ~/ 2));
    expect(at(400, 575), lessThan(at(400, 550) ~/ 2));
  });

  testWithFlameGame('in a world in metres a bulb mirrors as a bulb', (
    game,
  ) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    // A hundred pixels a metre: the view 8 m by 6 m.
    game.camera.viewfinder
      ..anchor = Anchor.topLeft
      ..zoom = 100;
    game.world.addAll([
      WaterSurface(
        position: Vector2(0, 4),
        size: Vector2(8, 2),
        shape: WaterShape.rect,
        color: const Color(0xFF000000),
        fade: 0,
      ),
      // A bulb 5 cm across, a metre over the water.
      LightSource(position: Vector2(4, 3), radius: 1, sourceRadius: 0.05),
      Lighting(skyLight: 0, glow: 0, haze: 0),
    ]);
    await game.ready();
    final at = await _render(game);
    // Mirrored a metre under the line: (400, 500) on screen.
    expect(at(400, 500), greaterThan(200));
    expect(at(400, 530), lessThan(40), reason: 'a bulb, not a disc of light');
    expect(at(430, 500), lessThan(40));
  });
}
