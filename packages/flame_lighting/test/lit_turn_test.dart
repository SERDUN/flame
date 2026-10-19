import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws a rect of [color] through the lighting's [Lighting.unlit], as its
/// own drawing.
class _Unlit extends Component {
  _Unlit(this.rect, this.color, {required int priority})
    : super(priority: priority);

  final Rect rect;
  final Color color;

  @override
  void render(Canvas canvas) {
    void draw() => canvas.drawRect(rect, Paint()..color = color);
    final lighting = Lighting.of(this);
    if (lighting == null) {
      draw();
    } else {
      lighting.unlit(canvas, draw, by: this);
    }
  }
}

/// Draws nothing at all - but nothing says so, and the lighting may not
/// take a layer it may have drawn into for empty.
class _Nothing extends Component {
  _Nothing({required int priority}) : super(priority: priority);

  @override
  void render(Canvas canvas) {}
}

Future<Uint8List> _draw(FlameGame game) async {
  game.update(1 / 60);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  return (await image.toByteData())!.buffer.asUint8List();
}

Future<Uint8List> _scene(FlameGame game, {required bool between}) async {
  await LightShader.load(directory: 'shaders');
  game.onGameResize(Vector2(800, 600));
  game.camera.viewfinder.anchor = Anchor.topLeft;
  game.world.addAll([
    // A board far behind the street line, by a lamp: lit by its cut, out
    // of the lamp's reach; and one on the line, in reach.
    RectangleComponent(
      position: Vector2(250, 200),
      size: Vector2(100, 200),
      paint: Paint()..color = const Color(0xFFFFFFFF),
      priority: -10,
    ),
    // Two drawn unlit one right after the other, and the board's cut
    // right after them, as a veil at the cut's depth is.
    _Unlit(
      const Rect.fromLTWH(600, 0, 100, 100),
      const Color(0x80FFFFFF),
      priority: -9,
    ),
    if (between) _Nothing(priority: -8),
    _Unlit(
      const Rect.fromLTWH(650, 50, 100, 100),
      const Color(0x8000FF00),
      priority: -7,
    ),
    if (between) _Nothing(priority: -6),
    LitCut(ahead: () => -1000, priority: -5),
    RectangleComponent(
      position: Vector2(450, 200),
      size: Vector2(100, 200),
      paint: Paint()..color = const Color(0xFFFFFFFF),
    ),
    LightSource(position: Vector2(400, 300), radius: 300),
    Lighting(skyLight: 0, glow: 0, lightsBackdrop: false),
  ]);
  await game.ready();
  return _draw(game);
}

void main() {
  setUp(() {
    LitLayer.turns = 0;
    LitLayer.emptyTurns = 0;
  });

  testWithFlameGame(
    'a layer opened right before the next unlit draw or cut holds nothing, '
    'and is not lit',
    (game) async {
      final drawn = await _scene(game, between: false);
      // The first unlit draw lights what is under it; the second and the
      // cut follow a turn with nothing between.
      expect(LitLayer.turns, 1);
      expect(LitLayer.emptyTurns, 2);
      expect(drawn[(300 * 800 + 300) * 4], lessThan(10), reason: 'far back');
      expect(drawn[(300 * 800 + 500) * 4], greaterThan(60), reason: 'lit');
    },
  );

  // The same scene with something between them that draws nothing: each
  // turn is made, and the picture is the same, pixel for pixel.
  late Uint8List skipped;
  testWithFlameGame('(the scene with the empty turns left out)', (game) async {
    skipped = await _scene(game, between: false);
  });
  testWithFlameGame(
    'leaving the empty turns out changes no pixel of the picture',
    (game) async {
      final every = await _scene(game, between: true);
      expect(LitLayer.turns, 3);
      expect(LitLayer.emptyTurns, 0);
      expect(every, orderedEquals(skipped));
    },
  );
}
