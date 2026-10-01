import 'dart:ui';

import 'package:flame/components.dart';
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
}
