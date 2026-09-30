import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Holder extends PositionComponent with Facing {
  _Holder() : super(size: Vector2(40, 90));

  @override
  double facing = 1;
}

void main() {
  testWithFlameGame('a torch turns round with the one holding it', (
    game,
  ) async {
    final holder = _Holder();
    final torch = Torch(hold: Vector2(28, 50));
    await holder.add(torch);
    await game.world.add(holder);
    await game.ready();
    expect(torch.position, Vector2(28, 50));
    expect(torch.coneDirection, closeTo(torch.tilt, 1e-9));

    holder.facing = -1;
    game.update(0);
    expect(torch.position, Vector2(12, 50), reason: 'the other hand');
    expect(torch.coneDirection, closeTo(math.pi - torch.tilt, 1e-9));
  });
}
