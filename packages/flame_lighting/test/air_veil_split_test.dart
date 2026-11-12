import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down: the street line at 400.
class _Ground extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 200);
}

/// A dry still day with [banks] of air over it.
class _Air extends Component with OnStage, Weather {
  _Air(this.banks);

  final List<AirBank> banks;

  @override
  double get rainMmPerHour => 0;

  @override
  Vector2 get wind => Vector2.zero();

  @override
  List<AirBank> get airBanks => banks;
}

/// A night street by a lamp, a fog over it, its veil and the ground's air
/// laid out of the multiply or into the lit layer as [splits] says.
Future<Uint8List> _scene(
  FlameGame game, {
  required bool Function() splits,
  bool fog = true,
  double Function()? resolution,
  Color horizon = const Color(0xFF00FF00),
  double skyLight = 0,
}) async {
  await LightShader.load(directory: 'shaders');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    RectangleComponent(
      size: Vector2(800, 600),
      paint: Paint()..color = const Color(0xFFFFFFFF),
    ),
    _Ground(),
    _Air([
      if (fog) AirBank(extinction: AirField.ofVisibility(50), topM: 1e6),
    ]),
    AirVeil(depth: () => -0.5, splitsLayer: splits, resolution: resolution),
    GroundAir(
      veils: () => const [],
      splitsLayer: splits,
      resolution: resolution,
    ),
    LightSource(position: Vector2(400, 300), radius: 300),
    Lighting(metre: 50, skyLight: skyLight, glow: 0, lightsBackdrop: false),
  ]);
  await game.ready();
  game.update(1 / 60);
  // The air's light is the sky's at the horizon: a green one, to be seen.
  Stage.maybeOf(game.world)!.frame.sky.set(
    topY: 0,
    horizonY: 400,
    top: horizon,
    horizon: horizon,
  );
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  return (await image.toByteData())!.buffer.asUint8List();
}

void main() {
  setUp(() {
    LitLayer.turns = 0;
    LitLayer.emptyTurns = 0;
  });

  testWithFlameGame('laid as light, the air turns the lit layer', (
    game,
  ) async {
    await _scene(game, splits: () => true);
    expect(LitLayer.turns + LitLayer.emptyTurns, greaterThan(0));
  });

  testWithFlameGame(
    'drawn into the lit layer, the air turns no layer and is still drawn',
    (game) async {
      final inLayer = await _scene(game, splits: () => false);
      expect(LitLayer.turns, 0);
      expect(LitLayer.emptyTurns, 0);
      final clear = await _scene(
        await initializeFlameGame(),
        splits: () => false,
        fog: false,
      );
      var differ = 0;
      for (var i = 0; i < inLayer.length; i += 4) {
        if ((inLayer[i] - clear[i]).abs() > 8) {
          differ++;
        }
      }
      expect(differ, greaterThan(10000), reason: 'the fog is in the picture');
    },
  );

  testWithFlameGame(
    'on a grid, drawn into the lit layer the air comes out as the light it was '
    'laid as, by the lamp too',
    (game) async {
      // A night's air: dimmer than the light that falls on it, as in a game.
      const night = Color(0xFF203820);
      final laid = await _scene(
        game,
        splits: () => true,
        resolution: () => 0.5,
        horizon: night,
        skyLight: 0.3,
      );
      LitLayer.turns = 0;
      LitLayer.emptyTurns = 0;
      final spared = await _scene(
        await initializeFlameGame(),
        splits: () => false,
        resolution: () => 0.5,
        horizon: night,
        skyLight: 0.3,
      );
      expect(LitLayer.turns + LitLayer.emptyTurns, 0);
      // By the lamp, away from it, in the sky and on the ground.
      for (final (x, y) in [
        (400, 300),
        (420, 380),
        (100, 100),
        (700, 200),
        (300, 500),
      ]) {
        final i = (y * 800 + x) * 4;
        for (var c = 0; c < 3; c++) {
          expect(
            (spared[i + c] - laid[i + c]).abs(),
            lessThanOrEqualTo(6),
            reason: 'at $x, $y, channel $c',
          );
        }
      }
    },
  );
}
