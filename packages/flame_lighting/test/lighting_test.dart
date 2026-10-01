import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wall filling the view, so any light shows as brightness.
class _Wall extends RectangleComponent {
  _Wall(Color color)
    : super(size: Vector2(800, 600), paint: Paint()..color = color);
}

/// The ground from y 400 down.
class _Ground extends Component with OnStage, Ground {
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

/// A post standing in the light's way, at a [depth] of the street.
class _Post extends Component with OnStage, ShadowCaster {
  _Post(this.x, this.top, this.bottom, {this.depth = 0});

  final double x;
  final double top;
  final double bottom;
  final double depth;

  @override
  void castShadow(ShadowSet shadows) => shadows.capsule(
    x,
    top,
    x,
    bottom,
    radius: 6,
    ahead: stage?.frame.projection?.ahead(depth) ?? 0,
    thickness: 30,
  );
}

/// The moon.
class _Moon extends Component with OnStage, LightCarrier {
  _Moon(this.intensity);

  final double intensity;

  @override
  Iterable<Light> get lights => [Light.directional(intensity: intensity)];
}

/// Brightness (red channel, 0..255) of the rendered game at a pixel.
Future<int Function(int x, int y)> _render(FlameGame game) async {
  game.update(1 / 60);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 800 + x) * 4);
}

Future<void> _setUp(
  FlameGame game,
  List<Component> extra, {
  double darkness = 1,
  double haze = 0,
  double glow = 0,
  Color wall = const Color(0xFFFFFFFF),
}) async {
  await LightShader.load(directory: 'shaders');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    _Wall(wall),
    Lighting(
      ambient: const Color(0xFF000000),
      darkness: darkness,
      glow: glow,
      haze: haze,
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

  testWithFlameGame('by day with no light on it draws nothing', (game) async {
    await _setUp(
      game,
      [
        LightSource(position: Vector2(400, 300), onAtDarkness: 0.3),
      ],
      darkness: 0,
      wall: const Color(0xFF808080),
    );
    final at = await _render(game);
    expect(at(400, 300), 0x80, reason: 'the lamp off, the wall as it is');
    expect(at(100, 100), 0x80);
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

  testWithFlameGame('a cone has no hard edge: light eases off to its sides', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 200), radius: 300, coneAngle: 1.6),
    ]);
    final at = await _render(game);
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
    'a lamp lays its pool from how its light falls on the ground',
    (game) async {
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
      final under = at(400, 405);
      expect(under, greaterThan(40));
      expect(at(560, 405), lessThan(under));
      expect(at(400, 540), lessThan(under));
      expect(at(100, 405), lessThan(5), reason: 'outside the cone');
    },
  );

  testWithFlameGame('a post on the road casts its shadow along it', (
    game,
  ) async {
    await _setUp(
      game,
      [
        _Ground(),
        // A lamp and a post at the same depth on the road (depth 0.1, row
        // 415): the post's shadow runs along that row away from the lamp.
        LightSource(position: Vector2(400, 330), radius: 600, depth: 0.1),
        _Post(470, 360, 415, depth: 0.1),
      ],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _render(game);
    // The same distance from the lamp: past the post in its shadow, on the
    // other side lit.
    expect(at(540, 415), lessThan(at(260, 415) ~/ 2));
  });

  testWithFlameGame('a walker in front of a lamp shades the house front', (
    game,
  ) async {
    await _setUp(
      game,
      [
        _Ground(),
        // A lamp near the eye (depth 0.8, 554 in front of the line), a
        // walker between it and the house fronts (depth 0.4, 400 in front):
        // its shadow lands on the wall behind, larger - the way from the
        // lamp passes the walker 0.28 of the way, so x 400 on the walker is
        // x 660 on the wall.
        LightSource(position: Vector2(300, 300), radius: 1400, depth: 0.8),
        _Post(400, 260, 340, depth: 0.4),
      ],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _render(game);
    expect(at(660, 300), lessThan(at(660, 120) ~/ 2));
  });

  testWithFlameGame('a moving light drags the shadows with it', (game) async {
    final lamp = LightSource(
      position: Vector2(300, 330),
      radius: 600,
      depth: 0.1,
    );
    await _setUp(
      game,
      [_Ground(), lamp, _Post(470, 360, 415, depth: 0.1)],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    var at = await _render(game);
    // The lamp left of the post: the shadow right of it.
    expect(at(540, 415), lessThan(at(400, 415) ~/ 2));
    lamp.position.x = 640;
    at = await _render(game);
    // The lamp moved right of the post: the shadow swings to its left, and
    // the right is lit.
    expect(at(400, 415), lessThan(at(540, 415) ~/ 2));
  });

  testWithFlameGame('a shop window lights the wall from all of it', (
    game,
  ) async {
    await _setUp(
      game,
      [
        LightSource.of(
          Light.area(size: Vector2(160, 80)),
          position: Vector2(400, 300),
        ),
      ],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _render(game);
    // In front of its corner as bright as in front of its middle: the
    // whole window glows, not a point at its centre.
    expect((at(470, 360) - at(400, 360)).abs(), lessThan(12));
    expect(at(400, 360), greaterThan(40));
  });

  testWithFlameGame('the moon lifts the dark everywhere', (game) async {
    await _setUp(game, [_Moon(0.5)]);
    final at = await _render(game);
    expect(at(100, 100), inInclusiveRange(110, 145));
    expect(at(700, 500), inInclusiveRange(110, 145));
  });

  testWithFlameGame('a wet wall glints where the lamp falls on it', (
    game,
  ) async {
    await _setUp(game, [
      LightSource(position: Vector2(400, 300)),
      _WetWall(1),
    ], wall: const Color(0xFF808080));
    final at = await _render(game);
    expect(at(440, 340), greaterThan(at(360, 340) + 5), reason: 'glinting');
    expect(at(100, 100), lessThan(10), reason: 'nothing where it is dark');
  });
}
