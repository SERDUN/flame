import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

class _Block extends RectangleComponent with Reflectable {
  _Block({super.position, super.size, super.paint});
}

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _water = Color(0xFF000000);

/// Renders [surface] alone onto a 100x140 image and reads it back.
Future<Color Function(int x, int y)> _draw(WaterSurface surface) async {
  final recorder = PictureRecorder();
  surface.renderTree(Canvas(recorder));
  final image = await recorder.endRecording().toImage(100, 140);
  final bytes = (await image.toByteData())!;
  return (x, y) {
    final i = (y * 100 + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  };
}

WaterSurface _surface({double squash = 1}) => WaterSurface(
  position: Vector2(0, 100),
  size: Vector2(100, 40),
  shape: WaterShape.rect,
  color: _water,
  reflectivity: 1,
  squash: squash,
  fade: 0,
);

void main() {
  testWithFlameGame(
    'the water mirrors what is reflectable about its line, nothing else',
    (game) async {
      final surface = _surface();
      await game.world.addAll([
        // Above the water line, 20 tall: its reflection reaches 20 below.
        _Block(
          position: Vector2(40, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _red,
        ),
        RectangleComponent(
          position: Vector2(0, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _blue,
        ),
        surface,
      ]);
      await game.ready();
      final pixel = await _draw(surface);
      expect(pixel(50, 110), _red, reason: 'mirrored just below the line');
      expect(pixel(50, 130), _water, reason: 'nothing reflected past 20');
      expect(pixel(10, 110), _water, reason: 'not reflectable');
      expect(pixel(80, 110), _water);
    },
  );

  testWithFlameGame('a squashed reflection is shorter', (game) async {
    final surface = _surface(squash: 0.5);
    await game.world.addAll([
      _Block(
        position: Vector2(40, 80),
        size: Vector2(20, 20),
        paint: Paint()..color = _red,
      ),
      surface,
    ]);
    await game.ready();
    final pixel = await _draw(surface);
    expect(pixel(50, 105), _red);
    expect(pixel(50, 115), _water);
  });

  testWithFlameGame('a reflectable learns it is being drawn as a reflection', (
    game,
  ) async {
    final seen = <bool>[];
    final surface = _surface();
    await game.world.addAll([
      _Probe(position: Vector2(40, 80), onRender: seen.add),
      surface,
    ]);
    await game.ready();
    await _draw(surface);
    expect(seen, [true]);
    expect(ReflectionPass.isActive, isFalse);
  });

  testWithFlameGame('a splash on the water starts a ring there', (game) async {
    final surface = _surface();
    await game.world.add(surface);
    await game.ready();
    expect(surface.covers(Vector2(50, 120)), isTrue);
    expect(surface.covers(Vector2(50, 90)), isFalse);
    surface.splash(Vector2(50, 120));
    expect(surface.ripples.count, 1);
  });
}

class _Probe extends PositionComponent with Reflectable {
  _Probe({super.position, required this.onRender})
    : super(size: Vector2.all(10));

  final void Function(bool) onRender;

  @override
  void render(Canvas canvas) => onRender(ReflectionPass.isActive);
}
