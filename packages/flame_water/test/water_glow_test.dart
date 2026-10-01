import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brightness (red channel) of the rendered game at a pixel.
Future<int Function(int x, int y)> _render(FlameGame game) async {
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 800 + x) * 4);
}

/// A lamp at (400, 300) over water from the line 400 down, in a black night.
Future<WaterSurface> _scene(FlameGame game, {double streak = 0}) async {
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
    // The lamp as bright as white, not burnt out: shifts show.
    glowGain: 1,
  );
  game.world.addAll([
    water,
    LightSource(position: Vector2(400, 300), radius: 60),
    Lighting(ambient: const Color(0xFF000000), darkness: 1, glow: 0, haze: 0),
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
}
