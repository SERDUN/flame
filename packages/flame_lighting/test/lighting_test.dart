import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A white wall filling the view, so any light shows as brightness.
class _Wall extends RectangleComponent {
  _Wall()
    : super(
        size: Vector2(800, 600),
        paint: Paint()..color = const Color(0xFFFFFFFF),
      );
}

class _Water extends PositionComponent with LightMirror {
  _Water() : super(position: Vector2(0, 400), size: Vector2(800, 150));

  @override
  double get mirrorLine => 400;
  @override
  double get mirrorSquash => 1;
  @override
  double get mirrorStrength => 1;
  @override
  double get mirrorStretch => 1;
  @override
  Path mirrorClip() => Path()..addRect(toAbsoluteRect());
}

/// Brightness (red channel, 0..255) of the rendered game at a pixel.
Future<int Function(int x, int y)> _render(FlameGame game) async {
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 800 + x) * 4);
}

Future<void> _setUp(FlameGame game, List<Component> extra) async {
  game.camera.viewfinder.anchor = Anchor.topLeft;
  await game.world.addAll([
    _Wall(),
    Lighting(ambient: const Color(0xFF000000), darkness: 1, glow: 0),
    ...extra,
  ]);
  await game.ready();
}

void main() {
  testWithFlameGame('the night is dark except where a light falls', (
    game,
  ) async {
    await _setUp(game, [LightSource(position: Vector2(400, 300))]);
    final at = await _render(game);
    expect(at(400, 300), greaterThan(230), reason: 'at the light');
    expect(at(400, 400), lessThan(at(400, 330)), reason: 'fades');
    expect(at(100, 100), lessThan(10), reason: 'out of reach');
  });

  testWithFlameGame('a lamp lights the street below it, not the sky', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300), coneAngle: math.pi / 2),
    ]);
    final at = await _render(game);
    expect(at(400, 340), greaterThan(60));
    expect(at(400, 260), lessThan(10));
  });

  testWithFlameGame('wet ground shows the lamp mirrored below its line', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300), radius: 60),
      _Water(),
    ]);
    final at = await _render(game);
    // Mirrored 100 below the line at 400: around y 500, lit only near x 400.
    expect(at(400, 495), greaterThan(60));
    expect(at(700, 495), lessThan(10));
    // The lamp itself mirrored: nearly as bright as the lamp.
    expect(at(400, 500), greaterThan(at(400, 300) * 0.85));
  });

  testWithFlameGame('a cone has no hard edge: light eases off to its sides', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 200), radius: 300, coneAngle: 1.6),
    ]);
    final at = await _render(game);
    // Across the cone, 150 below the lamp: from its axis out past its edge.
    final row = [for (var x = 400; x < 640; x++) at(x, 350)];
    var steepest = 0;
    for (var i = 1; i < row.length; i++) {
      steepest = math.max(steepest, (row[i] - row[i - 1]).abs());
    }
    expect(row.first, greaterThan(50), reason: 'lit along the axis');
    expect(row.last, lessThan(5), reason: 'dark past the edge');
    expect(steepest, lessThan(8), reason: 'no step at the edge: $row');
  });
}
