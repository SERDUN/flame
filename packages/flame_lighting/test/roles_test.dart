import 'dart:math' as math;
import 'dart:ui';

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
  _projectionTests();
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

class _Road extends Component with Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 100);
}

void _projectionTests() {
  test(
    'one projection: where things stand, how big and how fast they pass',
    () {
      final road = _Road();
      // The band 100 tall: the street line 600 from the eye, the nearest
      // ground 200.
      expect(road.farDistance, 600);
      expect(road.scaleAt(0), closeTo(1, 1e-9));
      expect(road.scaleAt(1), closeTo(3, 1e-9));
      expect(road.scaleAt(-0.25), lessThan(1), reason: 'behind the line');
      expect(road.yAt(0), 400);
      expect(road.yAt(-1), 400, reason: 'the line hides the ground behind');
      expect(road.yAt(0.5), 450);
      expect(road.depthAt(road.yAt(0.3)), closeTo(0.3, 1e-9));
      // Equal steps of distance crowd towards the street line.
      final far = road.distanceAt(0) - road.distanceAt(0.25);
      final near = road.distanceAt(0.75) - road.distanceAt(1);
      expect(far, greaterThan(near * 3));
      expect(
        road.projectX(500, 1, 400),
        700,
        reason: 'near things pass faster',
      );
      expect(road.projectX(500, 0, 400), 500);
      expect(road.sinElevation(1), greaterThan(road.sinElevation(0)));
    },
  );
}
