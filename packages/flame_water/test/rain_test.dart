import 'dart:math' as math;
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

/// An umbrella's canopy at depth 0: a dome over (400, 300), 80 wide, 30 tall,
/// meeting only the drops falling within [thickness] of the street line.
class _Canopy extends Component with RainDeflector {
  _Canopy({this.thickness = 0.1});

  final double thickness;

  @override
  bool deflect(Vector2 from, Vector2 to, Vector2 velocity, double depth) =>
      depth.abs() <= thickness &&
      RainBounce.offDome(
        from: from,
        to: to,
        velocity: velocity,
        center: Vector2(400, 300),
        angle: 0,
        halfWidth: 80,
        height: 30,
      );
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
    game.world.addAll([_Ground(), road, puddle, roof, Rain()]);
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
      game.world.addAll([rain, open, covered]);
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
    game.world.addAll([rain, water]);
    await game.ready();
    expect(water.chop, closeTo(2, 1e-9));
    rain.intensity = 2;
    expect(water.chop, closeTo(8, 1e-9));
  });

  testWithFlameGame(
    'a steady rain holds things where wetting and drying meet',
    (game) async {
      final wall = _Wall();
      final rain = Rain(intensity: 0.3);
      game.world.addAll([rain, wall]);
      await game.ready();
      await _rainFor(game, 120);
      // wetRate 0.3 x 0.3 against dryRate 0.02: 0.09 / 0.11.
      expect(wall.wetness, closeTo(0.09 / 0.11, 0.01), reason: 'a drizzle');
      rain.intensity = 2;
      await _rainFor(game, 60);
      expect(wall.wetness, closeTo(0.6 / 0.62, 0.01), reason: 'a downpour');
    },
  );

  testWithFlameGame(
    'after the rain things dry to nothing, as fast as the weather dries',
    (game) async {
      final wall = _Wall()..wetness = 1;
      final rain = Rain(intensity: 0);
      game.world.addAll([rain, wall]);
      await game.ready();
      await _rainFor(game, 10);
      expect(wall.wetness, closeTo(math.exp(-0.2), 0.01));
      final before = wall.wetness;
      rain.drying = 4;
      await _rainFor(game, 10);
      expect(wall.wetness, closeTo(before * math.exp(-0.8), 0.01));
      rain.drying = 0;
      final still = wall.wetness;
      await _rainFor(game, 10);
      expect(wall.wetness, closeTo(still, 1e-9), reason: 'no drying at all');
    },
  );

  testWithFlameGame('a puddle dries slower than a wall', (game) async {
    final wall = _Wall()
      ..wetness = 1
      ..dryRate = 0.05;
    final puddle = WaterSurface()..wetness = 1;
    game.world.addAll([Rain(intensity: 0), wall, puddle]);
    await game.ready();
    await _rainFor(game, 30);
    expect(puddle.wetness, greaterThan(wall.wetness * 3));
  });

  test('water dries as long as it is deep', () {
    final film = WaterSurface(depth: 0.1, film: true);
    final puddle = WaterSurface();
    expect(film.dryRate, closeTo(0.02, 1e-9), reason: 'as the asphalt');
    expect(puddle.dryRate, closeTo(film.dryRate / 10, 1e-9));
    puddle.dryRate = 0.05;
    expect(puddle.dryRate, 0.05, reason: 'set outright');
  });

  test('a drop splashes only if it hits hard enough', () {
    // A 1 mm drop at its terminal ~4 m/s splashes; a 0.5 mm drizzle drop at
    // ~2 m/s only wets.
    expect(Rain.impactNumber(1, 4), greaterThan(Rain.splashThreshold));
    expect(Rain.impactNumber(0.5, 2), lessThan(Rain.splashThreshold));
  });

  testWithFlameGame('a puddle shrinks on drier ground', (game) async {
    final puddle = WaterSurface(size: Vector2(200, 40), wetness: 0.1);
    game.world.add(puddle);
    await game.ready();
    final small = puddle.outline().getBounds().width;
    puddle.wetness = 1;
    expect(puddle.outline().getBounds().width, greaterThan(small * 2));
    puddle.wetness = 0;
    expect(puddle.outline().getBounds().isEmpty, isTrue, reason: 'dry: gone');
    expect(puddle.covers(Vector2(100, 20)), isFalse);
  });

  test('a drop falling on a dome bounces up off it, slower', () {
    final from = Vector2(400, 255);
    final to = Vector2(400, 275);
    final velocity = Vector2(0, 300);
    final hit = RainBounce.offDome(
      from: from,
      to: to,
      velocity: velocity,
      center: Vector2(400, 300),
      angle: 0,
      halfWidth: 80,
      height: 30,
    );
    expect(hit, isTrue);
    expect(velocity.y, closeTo(-300 * RainBounce.restitution, 1e-6));
    expect(to.y, lessThan(270.0), reason: 'put back above the surface');
    final miss = Vector2(600, 275);
    expect(
      RainBounce.offDome(
        from: Vector2(600, 255),
        to: miss,
        velocity: Vector2(0, 300),
        center: Vector2(400, 300),
        angle: 0,
        halfWidth: 80,
        height: 30,
      ),
      isFalse,
    );
  });

  testWithFlameGame(
    'rain bounces off a canopy at its depth and counts it; the rest passes',
    (game) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(intensity: 2);
      game.world.addAll([_Ground(), _Canopy(), rain]);
      await game.ready();
      await _rainFor(game, 3);
      final bounced = rain.takeBounces();
      expect(bounced.count, greaterThan(0));
      expect(bounced.speed, greaterThan(2), reason: 'm/s, falling drops');
      expect(rain.takeBounces().count, 0, reason: 'taken');
      expect(rain.landed[null], greaterThan(0), reason: 'the rest lands');
    },
  );

  testWithFlameGame('no canopy depth, no bounce', (game) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final rain = Rain(intensity: 2);
    game.world.addAll([_Ground(), _Canopy(thickness: -1), rain]);
    await game.ready();
    await _rainFor(game, 3);
    expect(rain.takeBounces().count, 0);
  });

  testWithFlameGame('rain falls only where the cloud lets it', (game) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final rain = Rain(
      wind: Vector2.zero(),
      releaseShare: (x) => x < 400 ? 1 : 0,
      cloudTop: () => 50,
    );
    game.world.addAll([_Ground(), rain]);
    await game.ready();
    await _rainFor(game, 2);
    expect(rain.dropsInAir, greaterThan(0));
    expect(rain.dropXs.every((x) => x < 400 + 1), isTrue);
    expect(
      rain.dropYs.every((y) => y >= 50 - 60),
      isTrue,
      reason: 'born at the cloud',
    );
  });

  testWithFlameGame('each drop takes the wind where it is', (game) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final rain = Rain(
      wind: Vector2.zero(),
      windAt: (at, out) => out.setValues(at.y < 200 ? 6 : 0, 0),
    );
    game.world.addAll([_Ground(), rain]);
    await game.ready();
    await _rainFor(game, 2);
    expect(rain.dropVelocities.where((v) => v.x > 50), isNotEmpty);
  });

  testWithFlameGame('a slice draws only the rain at its depths', (game) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final rain = Rain(intensity: 2)..drawsItself = false;
    game.world.addAll([_Ground(), rain]);
    await game.ready();
    await _rainFor(game, 1);
    Future<int> lit(void Function(Canvas) draw) async {
      final recorder = PictureRecorder();
      draw(Canvas(recorder));
      final image = await recorder.endRecording().toImage(800, 600);
      final bytes = (await image.toByteData())!;
      var n = 0;
      for (var i = 3; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) > 0) {
          n++;
        }
      }
      return n;
    }

    expect(await lit(rain.render), 0, reason: 'it does not draw itself');
    final all = await lit((c) => RainSlice(rain).render(c));
    final behind = await lit((c) => RainSlice(rain, to: 0).render(c));
    final front = await lit((c) => RainSlice(rain, from: 0).render(c));
    expect(all, greaterThan(0));
    expect(behind, greaterThan(0));
    expect(front, greaterThan(behind), reason: 'more, and bigger, in front');
    expect(behind + front, greaterThanOrEqualTo(all));
  });

  testWithFlameGame(
    'a veil far behind is drawn by the slice holding its depth',
    (
      game,
    ) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(intensity: 2)
        ..drawsItself = false
        ..veils = [-1];
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 0.5);
      Future<int> lit(Component slice) async {
        final recorder = PictureRecorder();
        slice.render(Canvas(recorder));
        final image = await recorder.endRecording().toImage(800, 600);
        final bytes = (await image.toByteData())!;
        var n = 0;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) > 0) {
            n++;
          }
        }
        return n;
      }

      // Nothing but the veil falls behind -0.5: the drops start at -0.25.
      expect(await lit(RainSlice(rain, to: -0.5)), greaterThan(0));
      expect(await lit(RainSlice(rain, from: -0.9, to: -0.5)), 0);
    },
  );
}
