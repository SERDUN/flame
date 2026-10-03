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

const _horizon = Color(0xFF00FF00);

Future<({int r, int g}) Function(int x, int y)> _render(
  FlameGame game,
  List<AirBank> banks,
) async {
  await LightShader.load(directory: 'shaders');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    RectangleComponent(
      size: Vector2(800, 600),
      paint: Paint()..color = const Color(0xFFFFFFFF),
    ),
    _Ground(),
    _Air(banks),
    AirVeil(depth: () => -0.5),
    // Fifty units a metre: the eye 2.6 m up, the street line 24 m off, the
    // veil's depth some 480 m. Under the noon sky nothing is lit.
    Lighting(metre: 50),
  ]);
  await game.ready();
  game.update(1 / 60);
  Stage.maybeOf(game.world)!.frame.sky.set(
    topY: 0,
    horizonY: 400,
    top: _horizon,
    horizon: _horizon,
  );
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) {
    final i = (y * 800 + x) * 4;
    return (r: bytes.getUint8(i), g: bytes.getUint8(i + 1));
  };
}

void main() {
  testWithFlameGame(
    'in a thick fog the far is lost in the air, the ground before it not',
    (game) async {
      // One sees 50 m through it; what stands at the veil is 480 m off.
      final at = await _render(game, [
        AirBank(extinction: AirField.ofVisibility(50), topM: 1e6),
      ]);
      final far = at(100, 200);
      expect(far.r, lessThan(30), reason: 'white gone into the air');
      expect(far.g, greaterThan(200), reason: "the air's light: the horizon");
      expect(at(100, 500).r, 255, reason: 'the ground is nearer than it');
    },
  );

  testWithFlameGame(
    'a ground fog lies low: the feet in it, the tops above it clear',
    (game) async {
      final at = await _render(game, [
        AirBank(extinction: AirField.ofVisibility(50), topM: 1, topWidthM: 0.4),
      ]);
      expect(at(100, 30).r, greaterThan(200), reason: 'high up, clear');
      // 0.4 m up at the veil's distance, inside the fog; 2 m up above it.
      expect(at(100, 399).r, lessThan(at(100, 30).r - 100));
      expect(at(100, 395).r, greaterThan(200));
    },
  );
}
