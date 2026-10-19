import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// Something the water mirrors that counts how often it is drawn.
class _Post extends RectangleComponent with Reflectable {
  _Post() : super(position: Vector2(380, 300), size: Vector2(40, 100));

  int drawn = 0;

  @override
  void render(Canvas canvas) {
    drawn++;
    super.render(canvas);
  }
}

WaterSurface _water(double left, double top, double width, double height) =>
    WaterSurface(
      position: Vector2(left, top),
      size: Vector2(width, height),
      waterLine: 400,
    );

Future<void> _frame(FlameGame game) async {
  game.update(1 / 60);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  recorder.endRecording().dispose();
}

/// One drawing of [game] as pixels, 800 by 600.
Future<ByteData> _pixels(FlameGame game) async {
  game.update(1 / 60);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  return (await image.toByteData())!;
}

/// The red of the pixel at [x], [y].
int _red(ByteData bytes, int x, int y) => bytes.getUint8((y * 800 + x) * 4);

/// A white wall the length of the road over a road of water, the camera
/// moving [step] along it a drawing; what the road mirrors at [x] down
/// the water, drawing by drawing.
Future<List<int>> _walk(
  FlameGame game, {
  required int mirrorEvery,
  required double step,
  required int x,
}) async {
  await WaterShader.load(asset: 'shaders/water.frag');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    _Wall(),
    _water(-2000, 400, 8000, 200)
      ..shape = WaterShape.rect
      ..mirrorEvery = mirrorEvery,
  ]);
  await game.ready();
  final reds = <int>[];
  for (var i = 0; i < 6; i++) {
    game.camera.viewfinder.position = Vector2(i * step, 0);
    reds.add(_red(await _pixels(game), x, 410));
  }
  return reds;
}

class _Wall extends RectangleComponent with Reflectable {
  _Wall()
    : super(
        position: Vector2(-2000, 200),
        size: Vector2(8000, 200),
        paint: Paint()..color = const Color(0xFFFFFFFF),
      );
}

void main() {
  testWithFlameGame(
    'a mirror kept for the next drawing still mirrors the edge a moving '
    'view comes to',
    (game) async {
      // The view moves 30 units a drawing, and the road keeps its picture
      // for two: the leading edge of every second view was 30 units past
      // the kept picture, and mirrored nothing.
      final fresh = await _walk(game, mirrorEvery: 1, step: 30, x: 795);
      expect(fresh.toSet(), hasLength(1), reason: 'the same wall all along');
      final before = MirrorPass.recordings;
      final kept = await _walk(
        await initializeFlameGame(),
        mirrorEvery: 2,
        step: 30,
        x: 795,
      );
      expect(kept, fresh);
      // Drawn wider by the way the view goes, the picture is still kept:
      // the first, the one the view first moved off, and every second after.
      expect(MirrorPass.recordings - before, 4);
    },
  );

  testWithFlameGame('a road and two puddles on it draw the world once', (
    game,
  ) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final post = _Post();
    game.world.addAll([
      post,
      _water(0, 400, 800, 200)..shape = WaterShape.rect,
      _water(300, 420, 200, 40),
      _water(500, 470, 120, 40),
    ]);
    await game.ready();
    await _frame(game);
    final before = MirrorPass.recordings;
    post.drawn = 0;
    await _frame(game);
    expect(MirrorPass.recordings - before, 1);
    // Once in the street, once in the mirror all three read.
    expect(post.drawn, 2);
  });

  testWithFlameGame('each drawing of the world draws its mirror once, '
      'a frame drawn twice too', (game) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final post = _Post();
    game.world.addAll([
      post,
      _water(300, 420, 200, 40),
      _water(500, 470, 120, 40),
    ]);
    await game.ready();
    await _frame(game);
    final before = MirrorPass.recordings;
    // The same frame drawn again, as a screen faster than the steps does.
    final recorder = PictureRecorder();
    game.render(Canvas(recorder));
    recorder.endRecording().dispose();
    expect(MirrorPass.recordings - before, 1);
    // The stage itself is no thing water shows.
    final stage = game.world.children.whereType<Stage>().single;
    expect(MirrorPass.mirrors(stage), isFalse);
  });

  testWithFlameGame('kept for two drawings, the mirror is drawn every '
      'other one; a water coming into view has it drawn at once', (
    game,
  ) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final puddles = [
      _water(300, 420, 200, 40)..mirrorEvery = 2,
      _water(500, 470, 120, 40)..mirrorEvery = 2,
    ];
    game.world.addAll([_Post(), ...puddles]);
    await game.ready();
    await _frame(game);
    final before = MirrorPass.recordings;
    for (var i = 0; i < 8; i++) {
      await _frame(game);
    }
    expect(MirrorPass.recordings - before, 4);
    // One that keeps no picture: drawn every drawing again.
    final third = _water(100, 420, 100, 40);
    game.world.add(third);
    await game.ready();
    await _frame(game);
    final added = MirrorPass.recordings;
    await _frame(game);
    expect(MirrorPass.recordings - added, 1);
  });

  testWithFlameGame('a mirror drawn coarser asks for fewer pixels', (
    game,
  ) async {
    final water = _water(300, 420, 200, 40)..resolution = 0.8;
    final fine = water.mirrorPixels;
    water.mirrorScale = 0.5;
    expect(water.mirrorPixels, closeTo(fine / 2, 1e-9));
  });

  testWithFlameGame('water out of view draws nothing and mirrors nothing', (
    game,
  ) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final post = _Post();
    game.world.addAll([post, _water(2000, 420, 200, 40)]);
    await game.ready();
    await _frame(game);
    final before = MirrorPass.recordings;
    post.drawn = 0;
    await _frame(game);
    expect(MirrorPass.recordings - before, 0);
    expect(post.drawn, 1, reason: 'only in the street');
  });

  testWithFlameGame('what is hidden is not mirrored either', (game) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final post = _Post();
    final hidden = _Hidden()..add(post);
    game.world.addAll([hidden, _water(0, 400, 800, 200)]);
    await game.ready();
    await _frame(game);
    post.drawn = 0;
    await _frame(game);
    expect(post.drawn, 0);
  });
}

/// A group that is not drawn, and holds what water would mirror.
class _Hidden extends PositionComponent with HasVisibility {
  _Hidden() {
    isVisible = false;
  }
}
