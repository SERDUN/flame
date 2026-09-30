import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A white wall filling the view, so any light shows as brightness.
class _Wall extends RectangleComponent {
  _Wall(Color color)
    : super(size: Vector2(800, 600), paint: Paint()..color = color);
}

/// Still water below y 400: the glow mirrored about that line, plainly.
class _Water extends PositionComponent with LightMirror {
  _Water({this.headroom = 1})
    : super(position: Vector2(0, 400), size: Vector2(800, 150));

  /// How much brighter than drawn it will bring the glow back.
  final double headroom;

  @override
  void renderMirroredGlow(
    Canvas canvas,
    void Function(Canvas, double) glow,
  ) {
    canvas
      ..save()
      ..clipRect(toAbsoluteRect())
      ..translate(0, 800)
      ..scale(1, -1);
    glow(canvas, headroom);
    canvas.restore();
  }
}

/// The ground from y 400 down.
class _Ground extends Component with Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 150);
}

/// A wet wall right of x 400.
class _WetWall extends Component with Glossy {
  _WetWall(this.gloss);

  @override
  final double gloss;

  @override
  Path glossArea() => Path()..addRect(const Rect.fromLTWH(400, 250, 400, 150));
}

/// Brightness (red channel, 0..255) of the rendered game at a pixel.
Future<int Function(int x, int y)> _render(FlameGame game) async {
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 800 + x) * 4);
}

Future<void> _setUp(
  FlameGame game,
  List<Component> extra, {
  double haze = 0,
  double glow = 0,
  Rect? floor,
  Color wall = const Color(0xFFFFFFFF),
}) async {
  game.camera.viewfinder.anchor = Anchor.topLeft;
  await game.world.addAll([
    _Wall(wall),
    Lighting(
      ambient: const Color(0xFF000000),
      darkness: 1,
      glow: glow,
      haze: haze,
      floor: floor,
    ),
    ...extra,
  ]);
  await game.ready();
}

void main() {
  testWithFlameGame('the night is dark except where a light falls', (
    game,
  ) async {
    await _setUp(game, [LightSource(position: Vector2(400, 300))]);
    final at = await _render(game);
    expect(at(400, 300), greaterThan(230), reason: 'at the light');
    expect(at(400, 400), lessThan(at(400, 330)), reason: 'fades');
    expect(at(100, 100), lessThan(10), reason: 'out of reach');
  });

  testWithFlameGame('a lamp lights the street below it, not the sky', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300), coneAngle: math.pi / 2),
    ]);
    final at = await _render(game);
    expect(at(400, 340), greaterThan(60));
    expect(at(400, 260), lessThan(10));
  });

  testWithFlameGame('water shows the lamp itself, as bright as the lamp', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300), radius: 60),
      _Water(),
    ]);
    final at = await _render(game);
    // Mirrored about 400: the lamp at 300 shows at 500.
    expect(at(400, 500), greaterThan(at(400, 300) * 0.9));
    expect(at(700, 500), lessThan(10));
  });

  testWithFlameGame('a cone has no hard edge: light eases off to its sides', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 200), radius: 300, coneAngle: 1.6),
    ]);
    final at = await _render(game);
    // Across the cone, 150 below the lamp: from its axis out past its edge.
    final row = [for (var x = 400; x < 640; x++) at(x, 350)];
    var steepest = 0;
    for (var i = 1; i < row.length; i++) {
      steepest = math.max(steepest, (row[i] - row[i - 1]).abs());
    }
    expect(row.first, greaterThan(50), reason: 'lit along the axis');
    expect(row.last, lessThan(5), reason: 'dark past the edge');
    expect(steepest, lessThan(8), reason: 'no step at the edge: $row');
  });

  testWithFlameGame('in thick air a lamp glows round its bulb, above it too', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300), coneAngle: math.pi / 2),
    ], haze: 1);
    final at = await _render(game);
    expect(at(400, 280), greaterThan(40), reason: 'the halo above the bulb');
    expect(at(400, 60), lessThan(5), reason: 'not the whole sky');
  });

  testWithFlameGame(
    'a mirror with headroom gets the halo fainter, not the bulb',
    (game) async {
      Future<int Function(int, int)> mirrored(double headroom) async {
        game.world.removeAll(game.world.children);
        await game.ready();
        await _setUp(
          game,
          [
            LightSource(position: Vector2(400, 300), coneAngle: math.pi / 2),
            _Water(headroom: headroom),
          ],
          haze: 1,
          wall: const Color(0xFF000000),
        );
        return _render(game);
      }

      final plain = await mirrored(1);
      final bright = await mirrored(4);
      // The bulb at (400, 300) shows at (400, 500); its halo 20 above it
      // at (400, 520).
      expect(bright(400, 500), plain(400, 500), reason: 'the bulb as bright');
      expect(bright(400, 520), lessThan(plain(400, 520) * 0.5));
    },
  );

  testWithFlameGame(
    'a drop in front of a lamp flares, one behind it dims',
    (game) async {
      final lighting = Lighting(darkness: 1);
      await game.world.addAll([
        lighting,
        LightSource(position: Vector2(400, 300), radius: 300),
      ]);
      await game.ready();
      final at = Vector2(420, 300);
      final side = lighting.scatteredLightAt(at, 0);
      final front = lighting.scatteredLightAt(at, 200);
      final behind = lighting.scatteredLightAt(at, -200);
      expect(front, greaterThan(side * 5));
      expect(behind, lessThan(side));
      expect(
        side,
        closeTo(LightSource(radius: 300).lightAt(Vector2(20, 0)), 1e-9),
        reason: 'side-on: what reaches it',
      );
    },
  );

  testWithFlameGame(
    'a lamp lays its pool from how its light falls on the ground',
    (game) async {
      await LightingShader.load(asset: 'shaders/pool.frag');
      await _setUp(
        game,
        [
          _Ground(),
          // Hanging 150 over the ground at x 400, pointing straight down.
          LightSource(position: Vector2(400, 250), radius: 400, coneAngle: 1.6),
        ],
        wall: const Color(0xFF000000),
        glow: 1,
      );
      final at = await _render(game);
      // Near the street line, right under the lamp, the light comes in
      // steepest: brightest there, fading along the street and towards
      // the eye.
      final under = at(400, 405);
      expect(under, greaterThan(40));
      expect(at(560, 405), lessThan(under));
      expect(at(400, 540), lessThan(under));
      expect(at(100, 405), lessThan(5), reason: 'outside the cone');
    },
  );

  testWithFlameGame('a wet wall glints where the lamp falls on it', (
    game,
  ) async {
    // A grey wall: a white one could not get any brighter.
    await _setUp(game, [
      LightSource(position: Vector2(400, 300)),
      _WetWall(1),
    ], wall: const Color(0xFF808080));
    final at = await _render(game);
    // The lamp lights both sides alike; only the right one is wet.
    expect(at(440, 340), greaterThan(at(360, 340) + 5), reason: 'glinting');
    expect(at(100, 100), lessThan(10), reason: 'nothing where it is dark');
  });

  testWithFlameGame(
    'water mirrors a torch beam in the wet air, not only the torch',
    (
      game,
    ) async {
      await _setUp(
        game,
        [
          // A torch at (300, 300) shining right, over water from 400 down.
          LightSource(
            position: Vector2(300, 300),
            radius: 300,
            coneAngle: 0.6,
            coneDirection: 0,
            sourceRadius: 0,
          ),
          _Water(),
        ],
        glow: 0.5,
        haze: 1,
        wall: const Color(0xFF000000),
      );
      final at = await _render(game);
      // The beam at (450, 300), mirrored about 400 to (450, 500), far from the
      // torch; behind the torch there is no beam to mirror.
      expect(at(450, 500), greaterThan(at(150, 500) + 10));
    },
  );

  testWithFlameGame(
    'a torch tilted down lays a pool of light ahead on the ground',
    (
      game,
    ) async {
      await LightingShader.load(asset: 'shaders/pool.frag');
      await _setUp(game, [
        // Held 40 over the ground, shining right and a little down.
        LightSource(
          position: Vector2(300, 360),
          radius: 300,
          coneAngle: 0.6,
          coneDirection: 0.3,
          sourceRadius: 0,
        ),
        // The lighting finds the ground itself.
        _Ground(),
      ]);
      final at = await _render(game);
      // On the ground along the street line, where the beam itself never
      // reaches on screen: lit ahead of the torch, dark behind it. It
      // shines along the street, not towards the eye: the ground well in
      // front of the line is out of its reach.
      expect(at(460, 410), greaterThan(40));
      expect(at(150, 410), lessThan(5));
      expect(at(460, 520), lessThan(5));
    },
  );
}
