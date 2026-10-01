import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

class _Block extends RectangleComponent with Reflectable {
  _Block({
    super.position,
    super.size,
    super.paint,
    this.reflectionBase,
    this.groundDepth,
  });

  @override
  final double? reflectionBase;

  @override
  final double? groundDepth;
}

/// The ground from y 100 down, 40 deep.
class _Road extends Component with Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 100, 100, 40);
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
  return (int x, int y) {
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

  testWithFlameGame(
    'something standing nearer is mirrored about where it stands',
    (game) async {
      final surface = _surface();
      await game.world.addAll([
        // 10 tall, standing on y 105 - below the water line at 100, as
        // something nearer the eye stands lower in the view.
        _Block(
          position: Vector2(40, 85),
          size: Vector2(20, 10),
          paint: Paint()..color = _red,
          reflectionBase: 105,
        ),
        surface,
      ]);
      await game.ready();
      final pixel = await _draw(surface);
      // Its bottom 10 above its base mirrors to 10 below it: 115..125.
      expect(pixel(50, 120), _red, reason: 'mirrored about its own base');
      expect(pixel(50, 108), _water, reason: 'not about the water line');
    },
  );

  testWithFlameGame(
    'something at a depth is mirrored about where that depth meets the ground',
    (game) async {
      final surface = _surface();
      await game.world.addAll([
        _Road(),
        // At depth 0.125 of a ground band 40 deep from y 100: it stands on
        // y 105, as the block above does by its base.
        _Block(
          position: Vector2(40, 85),
          size: Vector2(20, 10),
          paint: Paint()..color = _red,
          groundDepth: 0.125,
        ),
        surface,
      ]);
      await game.ready();
      final pixel = await _draw(surface);
      // With a ground the water mirrors as much as its angle of view lets
      // it (Fresnel): red, dimmer.
      expect(pixel(50, 120).r, greaterThan(0.2), reason: 'about y 105');
      expect(pixel(50, 120).g, 0);
      expect(pixel(50, 108), _water);
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
      _Probe(seen: seen, position: Vector2(40, 80)),
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

  testWithFlameGame('a puddle fades out towards its rim, no hard line', (
    game,
  ) async {
    final surface = WaterSurface(
      position: Vector2(0, 100),
      size: Vector2(100, 40),
      color: _water,
      fade: 0,
      edgeSoftness: 0.5,
    );
    await game.world.addAll([
      _Block(
        position: Vector2(0, 40),
        size: Vector2(100, 60),
        paint: Paint()..color = _red,
      ),
      surface,
    ]);
    await game.ready();
    final pixel = await _draw(surface);
    final middle = pixel(50, 120).r;
    final nearRim = pixel(8, 120).r;
    expect(middle, greaterThan(0.9));
    expect(nearRim, inExclusiveRange(0.02, middle), reason: 'thinning out');
    expect(pixel(1, 101).a, lessThan(0.05), reason: 'nothing past the rim');
  });
}

class _Probe extends PositionComponent with Reflectable {
  _Probe({required this.seen, super.position}) : super(size: Vector2.all(10));

  /// Whether each render was a reflection.
  final List<bool> seen;

  @override
  void render(Canvas canvas) => seen.add(ReflectionPass.isActive);
}
