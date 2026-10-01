import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Road extends Component with Ground {
  Rect band = const Rect.fromLTWH(0, 400, 800, 100);

  @override
  Rect groundBand() => band;
}

class _Lamp extends PositionComponent with OnStage, LightCarrier {
  _Lamp(Vector2 at) : super(position: at);

  final Light bulb = Light.point(offset: Vector2(0, -10), radius: 50);

  @override
  Iterable<Light> get lights => [bulb];
}

class _Night extends Component with OnStage, Ambience {
  @override
  double darkness = 0.7;
  @override
  Color get ambient => const Color(0xFF000000);
  @override
  double get haze => 0.3;
  @override
  double get glow => 0.2;
}

class _Pole extends PositionComponent with OnStage, ShadowCaster {
  _Pole(Vector2 at) : super(position: at);

  @override
  void castShadow(ShadowSet shadows) =>
      shadows.upright(absolutePosition, height: 100, width: 6);
}

/// Reads the frame as it updates: the stage must have built it already.
class _Reader extends Component with OnStage {
  int? lightsSeen;

  @override
  void update(double dt) {
    super.update(dt);
    lightsSeen = stage!.frame.light.count;
  }
}

void main() {
  testWithFlameGame('one stage a world, made when first asked for', (
    game,
  ) async {
    final a = _Lamp(Vector2(100, 300));
    final b = _Lamp(Vector2(300, 300));
    game.world.addAll([a, b]);
    await game.ready();
    final stages = game.world.children.whereType<Stage>().toList();
    expect(stages, hasLength(1));
    expect(a.stage, same(stages.single));
    expect(stages.single.members<LightCarrier>(), [a, b]);
    b.removeFromParent();
    await game.ready();
    expect(stages.single.members<LightCarrier>(), [a]);
  });

  testWithFlameGame('the frame is built before the rest of the world updates', (
    game,
  ) async {
    final reader = _Reader();
    game.world.addAll([reader, _Lamp(Vector2(100, 300)), _Night()]);
    await game.ready();
    game.update(1 / 60);
    expect(reader.lightsSeen, 1);
  });

  testWithFlameGame(
    'the frame holds the projection, the lights on their carriers, the night',
    (
      game,
    ) async {
      final road = _Road();
      final lamp = _Lamp(Vector2(100, 300));
      game.world.addAll([road, lamp, _Night(), _Pole(Vector2(200, 400))]);
      await game.ready();
      game.update(1 / 60);
      final frame = Stage.of(road).frame;
      expect(frame.projection!.band, road.band);
      expect(frame.light.count, 1);
      expect(frame.light.xOf(0), 100);
      expect(frame.light.yOf(0), 290, reason: 'its offset on the lamp');
      expect(frame.light.darkness, 0.7);
      expect(frame.shadows.count, 1);
      lamp.position.x = 150;
      road.band = const Rect.fromLTWH(0, 380, 800, 100);
      game.update(1 / 60);
      expect(frame.light.xOf(0), 150, reason: 'it moves with its carrier');
      expect(frame.projection!.line, 380, reason: 'made anew each frame');
    },
  );

  testWithFlameGame('with no ambience it is day', (game) async {
    game.world.add(_Lamp(Vector2(100, 300)));
    await game.ready();
    game.update(1 / 60);
    final frame = game.world.children.whereType<Stage>().single.frame;
    expect(frame.light.darkness, 0);
  });
}
