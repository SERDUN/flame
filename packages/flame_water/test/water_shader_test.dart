import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stripes extends PositionComponent with Reflectable {
  _Stripes() : super(position: Vector2(0, 60), size: Vector2(100, 40));

  final Paint _red = Paint()..color = const Color(0xFFFF0000);
  final Paint _blue = Paint()..color = const Color(0xFF0000FF);

  @override
  void render(Canvas canvas) {
    // Vertical stripes 4 wide: any sideways shift of the reflection changes
    // which colour a pixel shows.
    for (var x = 0.0; x < size.x; x += 8) {
      canvas
        ..drawRect(Rect.fromLTWH(x, 0, 4, size.y), _red)
        ..drawRect(Rect.fromLTWH(x + 4, 0, 4, size.y), _blue);
    }
  }
}

/// The ground from y 100 down, 40 deep.
class _Road extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 100, 100, 40);
}

/// How high the bent road stands at world [x]: rising to the right, a fifth
/// of a unit a unit, level with the street line at x 50.
double _lift(double x) => 0.2 * (x - 50);

/// The street line of [_BentRoad] at world [x].
double _lineAt(double x) => 100 - _lift(x);

/// The ground from y 100 down, 40 deep, rising and falling across the view
/// as a bend in the road makes it.
/// Water that follows the street line where the ground bends: a pond's, not
/// a film on the road.
class _LineWater extends WaterSurface {
  _LineWater({
    super.position,
    super.size,
    super.shape,
    super.fade,
    super.color,
  });

  @override
  bool get followsStreetLine => true;
}

class _BentRoad extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 100, 100, 40);

  @override
  double groundLiftAt(double x) => _lift(x);
}

/// A wall standing on the bent street line all along it: red for 8 units
/// above the line in each column, blue for 22 above that.
class _BentWall extends PositionComponent with Reflectable {
  _BentWall() : super(size: Vector2(100, 100));

  final Paint _red = Paint()..color = const Color(0xFFFF0000);
  final Paint _blue = Paint()..color = const Color(0xFF0000FF);

  @override
  void render(Canvas canvas) {
    for (var x = 0; x < 100; x++) {
      final line = _lineAt(x + 0.5);
      canvas
        ..drawRect(Rect.fromLTRB(x.toDouble(), line - 8, x + 1.0, line), _red)
        ..drawRect(
          Rect.fromLTRB(x.toDouble(), line - 30, x + 1.0, line - 8),
          _blue,
        );
    }
  }
}

/// [surface] alone onto a 100x140 image: its pixels, RGBA.
Future<ByteData> _pixels(WaterSurface surface) async {
  final recorder = PictureRecorder();
  surface.renderTree(Canvas(recorder));
  final image = await recorder.endRecording().toImage(100, 140);
  return (await image.toByteData())!;
}

Future<List<int>> _row(WaterSurface surface, int y) async {
  final recorder = PictureRecorder();
  surface.renderTree(Canvas(recorder));
  final image = await recorder.endRecording().toImage(100, 140);
  final bytes = (await image.toByteData())!;
  return [for (var x = 0; x < 100; x++) bytes.getUint8((y * 100 + x) * 4)];
}

void main() {
  testWithFlameGame('a ring bends the reflection; still water does not', (
    game,
  ) async {
    await WaterShader.load(asset: 'shaders/water.frag');
    WaterSurface surface() => WaterSurface(
      position: Vector2(0, 100),
      size: Vector2(100, 40),
      shape: WaterShape.rect,
      fade: 0,
      color: const Color(0xFF000000),
    );
    final still = surface();
    final struck = surface();
    game.world.addAll([_Stripes(), still, struck]);
    await game.ready();
    struck
      ..splash(Vector2(50, 110))
      ..update(0.15);
    final flat = await _row(still, 110);
    final bent = await _row(struck, 110);
    final changed = [
      for (var x = 0; x < 100; x++)
        if ((flat[x] - bent[x]).abs() > 60) x,
    ];
    // Still water shows the stripes as the mirror does; the ring moves them
    // near where the drop hit and leaves the far ends alone.
    expect(changed, isNotEmpty);
    expect(
      changed.every((x) => (x - 50).abs() < 30),
      isTrue,
      reason: '$changed',
    );
  });

  testWithFlameGame(
    'on a bent road each column mirrors about the street line where it is',
    (game) async {
      await WaterShader.load(asset: 'shaders/water.frag');
      final surface = _LineWater(
        position: Vector2(0, 90),
        size: Vector2(100, 50),
        shape: WaterShape.rect,
        fade: 0,
        color: const Color(0xFF000000),
      )..liesOnGround = true;
      game.world.addAll([_BentRoad(), _BentWall(), surface]);
      await game.ready();
      final bytes = await _pixels(surface);
      int at(int x, int y, int channel) =>
          bytes.getUint8((y * 100 + x) * 4 + channel);
      for (final x in [8, 25, 50, 75, 92]) {
        final line = _lineAt(x + 0.5);
        // Just under the line: the red foot of the wall; past 8 below it,
        // the blue above the red - mirrored about this column's own line.
        final near = (line + 3).round();
        final far = (line + 16).round();
        expect(
          at(x, near, 0),
          greaterThan(at(x, near, 2) + 8),
          reason: 'red just below the line at x $x (y $near)',
        );
        expect(
          at(x, far, 2),
          greaterThan(at(x, far, 0) + 8),
          reason: 'blue 16 below the line at x $x (y $far)',
        );
        // Its top is the street line: nothing of it above.
        expect(
          at(x, (line - 2).round(), 3),
          0,
          reason: 'no water above the line at x $x',
        );
      }
    },
  );

  testWithFlameGame(
    'on a bent road a shore in front of the line follows the road too',
    (game) async {
      await WaterShader.load(asset: 'shaders/water.frag');
      // A shore 12 below the street line where the road stands level: the
      // rectangle's top where the ground stands highest (x 100, 10 up).
      final surface = _LineWater(
        position: Vector2(0, 102),
        size: Vector2(100, 38),
        shape: WaterShape.rect,
        fade: 0,
        color: const Color(0xFF000000),
      )..liesOnGround = true;
      game.world.addAll([_BentRoad(), surface]);
      await game.ready();
      final bytes = await _pixels(surface);
      int alpha(int x, int y) => bytes.getUint8((y * 100 + x) * 4 + 3);
      for (final x in [8, 25, 50, 75, 92]) {
        final shore = 112 - _lift(x + 0.5);
        expect(
          alpha(x, (shore - 2).round()),
          0,
          reason: 'no water above the shore at x $x',
        );
        expect(
          alpha(x, (shore + 2).round()),
          greaterThan(0),
          reason: 'water below the shore at x $x',
        );
      }
    },
  );

  testWithFlameGame(
    'through the shader too, a puddle shows its bottom and a pond does not',
    (game) async {
      await WaterShader.load(asset: 'shaders/water.frag');
      WaterSurface water(WaterMedium medium, double basinMm) => WaterSurface(
        position: Vector2(0, 100),
        size: Vector2(100, 40),
        shape: WaterShape.rect,
        color: const Color(0xFFFFFFFF),
        medium: medium,
        basinMm: basinMm,
        substance: Substance.metal,
        fade: 0,
      );
      final puddle = water(WaterMedium.clear, 20);
      final pond = water(WaterMedium.pond, 1500);
      game.world.addAll([_Road(), puddle, pond]);
      await game.ready();
      final shallow = await _row(puddle, 138);
      final deep = await _row(pond, 138);
      expect(shallow[50], greaterThan(100), reason: 'the bottom through it');
      expect(deep[50], lessThan(25), reason: 'its bed gone under a metre');
    },
  );
}
