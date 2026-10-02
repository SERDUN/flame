import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flame_water/src/mirror_pass.dart';
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

class _Flat extends RectangleComponent with LiesFlat {
  _Flat({super.position, super.size, super.paint});
}

class _Overlay extends RectangleComponent with OffStage {
  _Overlay({super.position, super.size, super.paint});
}

/// A ground that paints itself red where a mirror could catch it.
class _PaintedRoad extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 100, 100, 40);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(60, 80, 20, 20),
      Paint()..color = _red,
    );
  }
}

/// The ground from y 100 down, 40 deep.
class _Road extends Component with OnStage, Ground {
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
    'the water mirrors whatever stands above its line, about that line',
    (game) async {
      final surface = _surface();
      game.world.addAll([
        // Above the water line, 20 tall: its reflection reaches 20 below.
        _Block(
          position: Vector2(40, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _red,
        ),
        // No mark of any kind: it stands, so it is mirrored.
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
      expect(pixel(10, 110), _blue, reason: 'anything standing is mirrored');
      expect(pixel(80, 110), _water);
    },
  );

  testWithFlameGame(
    'what lies flat, the ground, an overlay and a light are not mirrored',
    (game) async {
      final surface = _surface();
      game.world.addAll([
        _Flat(
          position: Vector2(0, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _red,
        ),
        _Overlay(
          position: Vector2(25, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _red,
        ),
        _PaintedRoad(),
        surface,
      ]);
      await game.ready();
      final pixel = await _draw(surface);
      expect(pixel(10, 110), _water, reason: 'no height, no image');
      expect(pixel(35, 110), _water, reason: 'not a thing in the world');
      expect(pixel(70, 110), _water, reason: 'the ground lies flat');
      expect(MirrorPass.mirrors(LightSource()), isFalse);
      expect(MirrorPass.mirrors(RectangleComponent()), isTrue);
    },
  );

  testWithFlameGame(
    'a flat thing under a standing one leaves the standing one mirrored',
    (game) async {
      final surface = _surface();
      final holder = RectangleComponent(
        position: Vector2(40, 80),
        size: Vector2(20, 20),
        paint: Paint()..color = _red,
      )..add(_Flat(size: Vector2(20, 20), paint: Paint()..color = _blue));
      game.world.addAll([holder, surface]);
      await game.ready();
      final pixel = await _draw(surface);
      expect(pixel(50, 110), _red);
    },
  );

  testWithFlameGame(
    'where nothing stands across, the water shows the sky drawn above it',
    (game) async {
      final surface = _surface();
      game.world.add(surface);
      await game.ready();
      // Red at the horizon, at the water line; blue 40 above it.
      surface.stage!.frame.sky.set(
        topY: 60,
        horizonY: 100,
        top: _blue,
        horizon: _red,
      );
      final pixel = await _draw(surface);
      final near = pixel(50, 101);
      final far = pixel(50, 139);
      expect(near.r, greaterThan(0.9), reason: 'just below: the horizon');
      expect(far.b, greaterThan(0.9), reason: '39 below: the sky 39 above');
    },
  );

  testWithFlameGame(
    'the mirror shows a thing as lit where it stands: in the dark, dark',
    (game) async {
      final surface = _surface();
      game.world.addAll([
        _Block(
          position: Vector2(40, 80),
          size: Vector2(20, 20),
          paint: Paint()..color = _red,
        ),
        Lighting(skyLight: 0, glow: 0, lightsBackdrop: false),
        surface,
      ]);
      await game.ready();
      game.update(1 / 60);
      final pixel = await _draw(surface);
      final mirrored = pixel(50, 110);
      expect(
        mirrored.r,
        lessThan(0.1),
        reason: 'a red block in a night with no lamp is no red in the water',
      );
    },
  );

  testWithFlameGame(
    'a puddle shows its bottom; a pond a metre deep hides it in its colour',
    (game) async {
      const white = Color(0xFFFFFFFF);
      WaterSurface water(WaterMedium medium, double basinMm) => WaterSurface(
        position: Vector2(0, 100),
        size: Vector2(100, 40),
        shape: WaterShape.rect,
        color: white,
        medium: medium,
        basinMm: basinMm,
        substance: Substance.metal,
        fade: 0,
      );
      final puddle = water(WaterMedium.clear, 20);
      final pond = water(WaterMedium.pond, 1500);
      game.world.addAll([_Road(), puddle, pond]);
      await game.ready();
      // Low in the view, where water is seen most steeply and mirrors least,
      // and nothing stands across to mirror.
      final shallow = (await _draw(puddle))(50, 138);
      final deep = (await _draw(pond))(50, 138);
      expect(shallow.r, greaterThan(0.4), reason: 'the bottom through it');
      expect(deep.r, lessThan(0.1), reason: 'its bed gone under a metre');
      expect(deep.g, greaterThan(deep.r), reason: 'green-brown, not black');
    },
  );

  testWithFlameGame(
    'a film gives way to a puddle lying on it: one surface there',
    (game) async {
      const white = Color(0xFFFFFFFF);
      final film = WaterSurface(
        position: Vector2(0, 100),
        size: Vector2(100, 40),
        shape: WaterShape.rect,
        color: white,
        film: true,
        fade: 0,
      );
      final puddle = WaterSurface(
        position: Vector2(30, 110),
        size: Vector2(40, 20),
        edgeSoftness: 0,
      );
      game.world.addAll([_Road(), film, puddle]);
      await game.ready();
      final pixel = await _draw(film);
      // The film darkens the asphalt it soaks; where the puddle lies it
      // leaves the ground to the puddle.
      expect(pixel(10, 120).r, lessThan(0.75));
      expect(pixel(50, 120), white);
    },
  );

  testWithFlameGame(
    'something standing nearer is mirrored about where it stands',
    (game) async {
      final surface = _surface();
      game.world.addAll([
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
      game.world.addAll([
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

  testWithFlameGame(
    'water shows only what stands across from it, as far as its rings reach',
    (game) async {
      final surface = _surface();
      game.world.add(surface);
      await game.ready();
      // Rings bend its mirror by up to waveAmplitude: 5 at depth 1.
      final area = surface.reflectedArea;
      expect(area.left, -surface.waveAmplitude);
      expect(area.right, 100 + surface.waveAmplitude);
      expect(area.top, double.negativeInfinity, reason: 'any height');
      expect(ReflectionPass.area, isNull, reason: 'outside a reflection');
      Rect? during;
      ReflectionPass.run(surface, () => during = ReflectionPass.area);
      expect(during, area);
    },
  );

  testWithFlameGame('a squashed reflection is shorter', (game) async {
    final surface = _surface(squash: 0.5);
    game.world.addAll([
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
    game.world.addAll([
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
    game.world.add(surface);
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
    game.world.addAll([
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
