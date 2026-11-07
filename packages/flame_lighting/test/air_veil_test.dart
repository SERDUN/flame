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
  List<AirBank> banks, {
  double Function()? resolution,
  double Function()? pixelRatio,
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
    _Air(banks),
    AirVeil(
      depth: () => -0.5,
      resolution: resolution,
      pixelRatio: pixelRatio,
    ),
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
  return _picture(game);
}

Future<({int r, int g}) Function(int x, int y)> _picture(
  FlameGame game,
) async {
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
    "the grid is a share of the screen's pixels, not of the canvas's units",
    (game) async {
      final banks = [AirBank(extinction: AirField.ofVisibility(50), topM: 1e6)];
      var ratio = 1.0;
      await _render(
        game,
        banks,
        resolution: () => 0.5,
        pixelRatio: () => ratio,
      );
      final veil = game.world.children.whereType<AirVeil>().single;
      // A unit a pixel: half of the pixels its area covers (a little past
      // the view), and the cell on the far edge.
      final half = veil.gridCells!.width - 1;
      expect(half, inInclusiveRange(400, 440));
      // A game drawing in logical pixels on a screen of two to one: a unit
      // is two pixels, and half of them is as many as the units.
      ratio = 2;
      game.update(1 / 60);
      await _picture(game);
      expect(veil.gridCells!.width - 1, closeTo(2 * half, 1));
    },
  );

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

  testWithFlameGame(
    'worked out on a grid half as fine, the air is the same air',
    (game) async {
      var share = 1.0;
      final banks = [
        AirBank(extinction: AirField.ofVisibility(50), topM: 1, topWidthM: 0.4),
      ];
      final fine = await _render(game, banks, resolution: () => share);
      share = 0.5;
      game.update(1 / 60);
      final coarse = await _picture(game);
      // Up the veil, clear above the fog and in it; the last rows over its
      // line, where the grid's last cells are. (The fog's top, here sharp
      // within two pixels, is a cell softer: 396-397 differ.)
      for (final y in [30, 200, 380, 395, 398, 399]) {
        for (final x in [3, 100, 401, 797]) {
          expect(
            (coarse(x, y).r - fine(x, y).r).abs(),
            lessThanOrEqualTo(8),
            reason: 'at $x, $y',
          );
        }
      }
      // Under its line the veil lays nothing, coarse or fine.
      expect(coarse(100, 450).r, 255);
    },
  );
}
