import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flame_water/src/mirror_pass.dart';
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

void main() {
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
