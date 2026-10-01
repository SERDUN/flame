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

/// The sun, going [toward].
class _Sun extends Component with OnStage, LightCarrier {
  _Sun(this.toward);

  final Vector3 toward;

  @override
  Iterable<Light> get lights => [
    Light.sun(toward: toward, color: const Color(0xFFFFFFFF)),
  ];
}

/// The moon.
class _Moon extends Component with OnStage, LightCarrier {
  _Moon(this.intensity);

  final double intensity;

  @override
  Iterable<Light> get lights => [
    Light.directional(color: const Color(0xFFFFFFFF), intensity: intensity),
  ];
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
  double skyLight = 0,
  double haze = 0,
  double glow = 0,
  Color wall = const Color(0xFFFFFFFF),
}) async {
  await LightShader.load(directory: 'shaders');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    _Wall(wall),
    Lighting(skyLight: skyLight, glow: glow, haze: haze),
    ...extra,
  ]);
  await game.ready();
}

void main() {
  testWithFlameGame('under a dark sky only what a light falls on shows', (
    game,
  ) async {
    await _setUp(game, [LightSource(position: Vector2(400, 300))]);
    final at = await _render(game);
    expect(at(400, 300), greaterThan(230), reason: 'at the light');
    expect(at(400, 400), lessThan(at(400, 330)), reason: 'fades');
    expect(at(100, 100), lessThan(10), reason: 'out of reach');
  });

  testWithFlameGame('under the noon sky with no lamp on it draws nothing', (
    game,
  ) async {
    await _setUp(
      game,
      [
        // Its sensor switches it on below a sky of 2: noon is 40.
        LightSource(position: Vector2(400, 300), switchOnBelow: 2),
      ],
      skyLight: 40,
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

  testWithFlameGame('the moon lights everything alike', (game) async {
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

  testWithFlameGame('two lamps light two places in one frame', (game) async {
    await _setUp(
      game,
      [
        LightSource(
          position: Vector2(200, 300),
          color: const Color(0xFFFF0000),
        ),
        LightSource(
          position: Vector2(600, 300),
          color: const Color(0xFF0000FF),
        ),
      ],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _renderRgb(game);
    // Each draw keeps the uniforms it was given: the red lamp's light is
    // red, the blue one's blue (off the bulbs, which are near white).
    expect(at(200, 330).r, greaterThan(100));
    expect(at(200, 330).b, lessThan(10));
    expect(at(600, 330).b, greaterThan(100));
    expect(at(600, 330).r, lessThan(10));
  });

  testWithFlameGame('the shader lights as much as the field says', (
    game,
  ) async {
    final lamp = LightSource(
      position: Vector2(400, 200),
      radius: 300,
      coneAngle: 1.6,
      color: const Color(0xFFFFFFFF),
    );
    await _setUp(
      game,
      [lamp],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _render(game);
    final field = lamp.stage!.frame.light;
    // Along the axis, across the soft edge and out to the reach: the light
    // drawn and the light rain and walls are given agree.
    for (final (x, y) in const [
      (400, 260),
      (400, 400),
      (470, 330),
      (560, 330),
      (600, 300),
      (400, 480),
    ]) {
      final expected = (field.reach(0, x.toDouble(), y.toDouble(), 0) * 255)
          .clamp(0, 255);
      expect(at(x, y), closeTo(expected, 4), reason: 'at ($x, $y)');
    }
  });

  testWithFlameGame('a lamp shining down lights its own head', (game) async {
    final lamp = LightSource(
      position: Vector2(400, 200),
      radius: 300,
      coneAngle: 1.2,
      color: const Color(0xFFFFFFFF),
      spill: 0.8,
      spillRadius: 60,
    );
    await _setUp(
      game,
      [lamp],
      wall: const Color(0xFF000000),
      glow: 1,
    );
    final at = await _render(game);
    final field = lamp.stage!.frame.light;
    for (final (x, y) in const [
      (400, 170),
      (430, 190),
      (400, 150),
      (400, 300),
    ]) {
      final expected = (field.reach(0, x.toDouble(), y.toDouble(), 0) * 255)
          .clamp(0, 255);
      expect(at(x, y), closeTo(expected, 4), reason: 'at ($x, $y)');
    }
    expect(at(400, 170), greaterThan(40), reason: 'above the bulb, lit');
    expect(at(400, 130), lessThan(5), reason: 'past the spill, dark');
  });

  testWithFlameGame('a zoomed camera lights where the lamp is', (game) async {
    await LightShader.load(directory: 'shaders');
    game.onGameResize(Vector2(800, 600));
    game.camera.viewfinder
      ..anchor = Anchor.topLeft
      ..zoom = 2
      ..position = Vector2(300, 200);
    game.world.addAll([
      _Wall(const Color(0xFFFFFFFF)),
      Lighting(skyLight: 0, glow: 0, haze: 0),
      LightSource(position: Vector2(400, 300), radius: 60),
    ]);
    await game.ready();
    final at = await _render(game);
    // World (400, 300) is at ((400 - 300) * 2, (300 - 200) * 2) on screen.
    expect(at(200, 200), greaterThan(230));
    expect(at(400, 300), lessThan(10), reason: 'not at its world place');
  });

  testWithFlameGame('before the shader is loaded a light is a soft disc', (
    game,
  ) async {
    LightShader.reset();
    game.onGameResize(Vector2(800, 600));
    game.camera.viewfinder.anchor = Anchor.topLeft;
    game.world.addAll([
      _Wall(const Color(0xFFFFFFFF)),
      Lighting(skyLight: 0, glow: 0, haze: 0),
      LightSource(position: Vector2(400, 300)),
    ]);
    await game.ready();
    final at = await _render(game);
    expect(at(400, 300), greaterThan(230));
    expect(at(400, 380), lessThan(at(400, 320)));
    expect(at(100, 100), lessThan(10));
    await LightShader.load(directory: 'shaders');
  });

  testWithFlameGame('a wet wall in a scaled layer glints where the lamp is', (
    game,
  ) async {
    // The wall in a layer drawn at half size: its gloss area is still in
    // world coordinates, and its sheen must land there, not at half of it.
    final layer = PositionComponent(scale: Vector2.all(0.5))..add(_WetWall(1));
    await _setUp(game, [
      LightSource(position: Vector2(400, 300)),
      layer,
    ], wall: const Color(0xFF808080));
    final at = await _render(game);
    expect(at(440, 340), greaterThan(at(360, 340) + 5), reason: 'glinting');
  });

  testWithFlameGame('under a warm dusk sky a white wall takes its colour', (
    game,
  ) async {
    await _setUp(game, [], skyLight: 3);
    game.world.children.whereType<Lighting>().single.sky = const Color(
      0xFFFF9A4D,
    );
    final at = await _renderRgb(game);
    final wall = at(400, 300);
    expect(wall.r, greaterThan(wall.g));
    expect(wall.g, greaterThan(wall.b));
    expect(wall.r, greaterThan(200), reason: 'the eye adapts: not dark');
  });

  testWithFlameGame('a lamp carries the night and vanishes in the day', (
    game,
  ) async {
    await _setUp(game, [LightSource(position: Vector2(400, 300), radius: 200)]);
    final lighting = game.world.children.whereType<Lighting>().single;
    var at = await _render(game);
    final night = at(400, 380) - at(100, 100);
    lighting.skyLight = 40;
    at = await _render(game);
    final day = at(400, 380) - at(100, 100);
    expect(night, greaterThan(60));
    expect(day, lessThan(8), reason: 'a speck against the sky');
  });

  testWithFlameGame(
    "the sun lays a post's shadow along the road, away from it",
    (
      game,
    ) async {
      await _setUp(
        game,
        [
          _Ground(),
          // From the upper left, down onto the road and a little into it.
          _Sun(Vector3(1, 1, 0.2)),
          _Post(470, 330, 415, depth: 0.1),
        ],
      );
      final at = await _render(game);
      // The road at the post's row: lit to its left, shaded to its right.
      expect(at(420, 415), greaterThan(100), reason: 'lit');
      expect(
        at(520, 415),
        lessThan(at(420, 415) ~/ 3),
        reason: 'in its shadow',
      );
    },
  );
}

/// The rendered game's colour at a pixel.
Future<({int r, int g, int b}) Function(int x, int y)> _renderRgb(
  FlameGame game,
) async {
  game.update(1 / 60);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) {
    final i = (y * 800 + x) * 4;
    return (
      r: bytes.getUint8(i),
      g: bytes.getUint8(i + 1),
      b: bytes.getUint8(i + 2),
    );
  };
}
