import 'dart:io';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down to 520.
class _Ground extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 120);
}

/// How much light [slice] lays over black above the street line, and on how
/// many pixels.
Future<({int light, int pixels})> _streaks(Component slice) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xFF000000), BlendMode.src);
  slice.render(canvas);
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  // The haze lies evenly over all of it: what is above its level is
  // streaks.
  var base = 255;
  for (var i = 0; i < 800 * 330; i++) {
    final r = bytes.getUint8(i * 4);
    if (r < base) {
      base = r;
    }
  }
  var light = 0;
  var pixels = 0;
  for (var i = 0; i < 800 * 330; i++) {
    final r = bytes.getUint8(i * 4) - base;
    light += r;
    if (r > 3) {
      pixels++;
    }
  }
  return (light: light, pixels: pixels);
}

void main() {
  test('the veil shader reads what the Dart side writes', () {
    final source = File('shaders/veil.frag').readAsStringSync();
    final names = RegExp(
      r'#define\s+(\w+)\s+u\[(\d+)\]',
    ).allMatches(source).map((m) => '${m[1]}@${m[2]}').toList();
    expect(names, [
      'uView@0',
      'uTime@1',
      'uFall@1',
      'uLength@1',
      'uWidth@1',
      'uSlope@2',
      'uShift@2',
      'uColumn@2',
      'uShare@2',
      'uColor@3',
      'uPixel@4',
      'uSeed@4',
    ]);
    expect(source, contains('uniform vec4 u[5];'));
  });

  testWithFlameGame('a veil is streaks, as many as it rains', (game) async {
    await RainVeil.load(asset: 'shaders/veil.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    // At about a third of the street's scale: as far back as far decor.
    final rain = Rain(intensity: 2)
      ..veils = [-0.35]
      ..drawsItself = false;
    game.world.addAll([_Ground(), rain]);
    await game.ready();
    for (var i = 0; i < 30; i++) {
      game.update(1 / 30);
    }
    final hard = await _streaks(RainSlice(rain, to: -0.3));
    rain.intensity = 0.5;
    final soft = await _streaks(RainSlice(rain, to: -0.3));
    expect(hard.pixels, greaterThan(2000));
    expect(soft.pixels, lessThan(hard.pixels / 2));
  });

  testWithFlameGame(
    "a veil's haze is the air's light: the horizon drawn, not lit as a wall",
    (game) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(intensity: 2)
        ..veils = [-0.35]
        ..drawsItself = false;
      game.world.addAll([
        _Ground(),
        rain,
        // A night with no lamp: anything lit as a surface would be black.
        Lighting(skyLight: 0, glow: 0, lightsBackdrop: false),
      ]);
      await game.ready();
      for (var i = 0; i < 10; i++) {
        game.update(1 / 30);
      }
      rain.stage!.frame.sky.set(
        topY: 0,
        horizonY: 400,
        top: const Color(0xFF000000),
        horizon: const Color(0xFF00FF00),
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xFF000000), BlendMode.src);
      RainSlice(rain, to: -0.3).render(canvas);
      final image = await recorder.endRecording().toImage(800, 600);
      final bytes = (await image.toByteData())!;
      final at = (20 * 800 + 20) * 4;
      expect(bytes.getUint8(at + 1), greaterThan(4), reason: 'the green haze');
      expect(bytes.getUint8(at), lessThan(2), reason: 'not the rain colour');
    },
  );
}
