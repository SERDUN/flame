import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Thing extends Component with OnStage, AtDepth {
  _Thing(this.name, this.depth, [this.order = DepthOrder.standing]);

  final String name;
  final double depth;
  final DepthOrder order;

  @override
  double depthIn(StreetProjection? projection) => depth;

  @override
  DepthOrder get depthOrder => order;
}

class _Road extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 100, 100, 40);
}

void main() {
  testWithFlameGame('things are drawn far to near, whoever came first', (
    game,
  ) async {
    final near = _Thing('near', 0.5);
    final far = _Thing('far', -1);
    final line = _Thing('line', 0);
    game.world.addAll([near, _Road(), line, far]);
    await game.ready();
    game.update(1 / 60);
    await game.ready();
    final drawn = game.world.children
        .whereType<_Thing>()
        .map((t) => t.name)
        .toList();
    expect(drawn, ['far', 'line', 'near']);
  });

  testWithFlameGame(
    'at one depth: the ground, what lies on it, rain, what stands, air, light',
    (game) async {
      final things = [
        _Thing('light', 0, DepthOrder.light),
        _Thing('air', 0, DepthOrder.air),
        _Thing('stands', 0),
        _Thing('rain', 0, DepthOrder.rain),
        _Thing('flat', 0, DepthOrder.flat),
      ];
      final road = _Road();
      game.world.addAll([...things, road]);
      await game.ready();
      game.update(1 / 60);
      await game.ready();
      final drawn = [
        for (final c in game.world.children)
          if (c is _Thing) c.name else if (c is _Road) 'ground',
      ];
      expect(drawn, ['ground', 'flat', 'rain', 'stands', 'air', 'light']);
    },
  );
}
