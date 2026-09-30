import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down to 520.
class _Ground extends Component with Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 120);
}

/// A roof at y 200 across x 100..300: it catches the rain behind the street
/// line.
class _Roof extends Component with RainCatcher {
  final List<double> depths = [];

  @override
  double? catchDrop(double x, double fromY, double toY, double depth) =>
      depth < 0 && x >= 100 && x <= 300 && fromY < 200 && toY >= 200
      ? 200
      : null;

  @override
  void onDrop(Vector2 at, double strength) => depths.add(at.y);
}

class _Wall extends Component with Wettable {
  _Wall({this.sheltered = false});

  @override
  final bool sheltered;
}

Future<void> _rainFor(FlameGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    game.update(1 / 30);
  }
}

void main() {
  testWithFlameGame('rain lands in the puddle over the road, on the road '
      'beside it and on a roof by the far drops', (game) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final road = WaterSurface(
      position: Vector2(0, 400),
      size: Vector2(800, 120),
      shape: WaterShape.rect,
      depth: 0.1,
      film: true,
    );
    final puddle = WaterSurface(
      position: Vector2(300, 420),
      size: Vector2(300, 80),
    );
    final roof = _Roof();
    await game.world.addAll([_Ground(), road, puddle, roof, Rain()]);
    await game.ready();
    await _rainFor(game, 3);
    expect(puddle.ripples.count, greaterThan(0), reason: 'the puddle');
    expect(road.ripples.count, greaterThan(0), reason: 'the road beside it');
    expect(roof.depths, isNotEmpty, reason: 'the roof');
    // A drop the puddle covers is the puddle's, not the road's.
    expect(puddle.catchOrder, greaterThan(road.catchOrder));
  });

  testWithFlameGame(
    'things get wet in the rain, dry after it, not under cover',
    (
      game,
    ) async {
      final rain = Rain();
      final open = _Wall();
      final covered = _Wall(sheltered: true);
      await game.world.addAll([rain, open, covered]);
      await game.ready();
      await _rainFor(game, 5);
      expect(open.wetness, greaterThan(0.6));
      expect(covered.wetness, 0);
      rain.intensity = 0;
      final soaked = open.wetness;
      await _rainFor(game, 10);
      expect(
        open.wetness,
        inExclusiveRange(0, soaked),
        reason: 'drying slowly',
      );
    },
  );

  testWithFlameGame('water is as astir as the rain over it is hard', (
    game,
  ) async {
    final rain = Rain(intensity: 0.5);
    final water = WaterSurface(chopPerRain: 4);
    await game.world.addAll([rain, water]);
    await game.ready();
    expect(water.chop, closeTo(2, 1e-9));
    rain.intensity = 2;
    expect(water.chop, closeTo(8, 1e-9));
  });

  testWithFlameGame('rain soaks things only as wet as they can get', (
    game,
  ) async {
    final wall = _Wall()..wetnessCap = 0.3;
    await game.world.addAll([Rain(), wall]);
    await game.ready();
    await _rainFor(game, 20);
    expect(wall.wetness, closeTo(0.3, 0.02));
    wall.wetnessCap = 0.1;
    await _rainFor(game, 200);
    expect(wall.wetness, lessThan(0.15), reason: 'drying down to the cap');
  });

  testWithFlameGame('a puddle shrinks on drier ground', (game) async {
    final puddle = WaterSurface(size: Vector2(200, 40), wetness: 0.1);
    await game.world.add(puddle);
    await game.ready();
    final small = puddle.outline().getBounds().width;
    puddle.wetness = 1;
    expect(puddle.outline().getBounds().width, greaterThan(small * 2));
  });
}
