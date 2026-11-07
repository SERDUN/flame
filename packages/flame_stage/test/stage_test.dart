import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Road extends Component with OnStage, Ground {
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
  Color get sky => const Color(0xFF8090FF);
  @override
  double skyLight = 0.3;
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

/// Writes into [log] when the frame is prepared.
class _Step extends Component with OnStage, FrameStep {
  _Step(this.log);

  final List<String> log;

  @override
  void prepareFrame(Canvas canvas, StageFrame frame) =>
      log.add('prepared ${frame.index}');
}

/// Writes into [log] when it draws.
class _Drawer extends Component {
  _Drawer(this.log) : super(priority: -100);

  final List<String> log;

  @override
  void render(Canvas canvas) => log.add('drawn');
}

void main() {
  testWithFlameGame('a world is its own world', (game) async {
    expect(Stage.worldOf(game.world), same(game.world));
  });

  testWithFlameGame('a frame step runs before anything in the world draws', (
    game,
  ) async {
    final log = <String>[];
    // The drawer has the lower priority, and is added first.
    game.world.addAll([_Drawer(log), _Step(log)]);
    await game.ready();
    game.update(1 / 60);
    game.render(Canvas(PictureRecorder()));
    expect(log, ['prepared 1', 'drawn']);
  });

  testWithFlameGame('a frame step runs once a frame, the world drawn twice', (
    game,
  ) async {
    final log = <String>[];
    game.world.addAll([_Drawer(log), _Step(log)]);
    await game.ready();
    game.update(1 / 60);
    // A mirror draws the world again, the stage with it.
    game.render(Canvas(PictureRecorder()));
    game.world.children.whereType<Stage>().single.renderTree(
      Canvas(PictureRecorder()),
    );
    game.update(1 / 60);
    game.render(Canvas(PictureRecorder()));
    expect(log, ['prepared 1', 'drawn', 'prepared 2', 'drawn']);
  });

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
      expect(frame.light.skyBlue, closeTo(0.3, 1e-6));
      expect(frame.light.exposure, 1);
      expect(frame.shadows.count, 1);
      lamp.position.x = 150;
      road.band = const Rect.fromLTWH(0, 380, 800, 100);
      game.update(1 / 60);
      expect(frame.light.xOf(0), 150, reason: 'it moves with its carrier');
      expect(frame.projection!.line, 380, reason: 'made anew each frame');
    },
  );

  testWithFlameGame('with no ambience the scene is drawn unlit', (game) async {
    game.world.add(_Lamp(Vector2(100, 300)));
    await game.ready();
    game.update(1 / 60);
    final frame = game.world.children.whereType<Stage>().single.frame;
    expect(frame.light.lit, isFalse);
    expect(frame.light.isLit, isFalse);
  });
}
