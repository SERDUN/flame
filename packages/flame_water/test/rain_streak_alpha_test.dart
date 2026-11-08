import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down to 520.
class _Ground extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 120);
}

Future<void> _rainFor(FlameGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    game.update(1 / 30);
  }
}

/// The share of the light a streak's point hides, as the rain draws it:
/// Garg & Nayar's `a = 2 r0 / (v T)` times the focus share, the light left
/// out.
void main() {
  group('the streak fill follows Garg & Nayar', () {
    test('a drop hides the share of the light its size and speed give', () {
      // a = D / (v T), the drop's diameter in metres over its speed and the
      // shutter.
      expect(
        RainDrops.streakFill(2, 6.547699616675644),
        closeTo(
          0.002 / 6.547699616675644 / RainDrops.alphaExposureSec,
          1e-12,
        ),
      );
    });

    test("the fill rises with the drop's size", () {
      final small = RainDrops.streakFill(0.5, 4);
      final middle = RainDrops.streakFill(1, 4);
      final large = RainDrops.streakFill(2, 4);
      expect(middle, greaterThan(small));
      expect(large, greaterThan(middle));
      // Twice the diameter, twice the fill at the same speed.
      expect(large / middle, closeTo(2, 1e-12));
    });

    test("the fill falls with the drop's speed", () {
      final slow = RainDrops.streakFill(1, 2);
      final fast = RainDrops.streakFill(1, 8);
      expect(fast, lessThan(slow));
      // Four times the speed, a quarter of the fill.
      expect(fast / slow, closeTo(0.25, 1e-12));
    });

    test('the fill rises as the shutter shortens', () {
      // The same drop at the same speed, at the length's own 1/20 s and at the
      // alpha's 1/1375 s: the shorter the exposure, the longer each point of
      // the streak sees the drop, and the more of the light it hides.
      final long = RainDrops.streakFill(
        2,
        6.5,
        exposureSec: RainDrops.exposureSec,
      );
      final short = RainDrops.streakFill(2, 6.5);
      expect(short, greaterThan(long));
      expect(
        long / short,
        closeTo(RainDrops.alphaExposureSec / RainDrops.exposureSec, 1e-12),
      );
      // Half the shutter, twice the fill.
      expect(
        RainDrops.streakFill(1, 4, exposureSec: 0.001) /
            RainDrops.streakFill(1, 4, exposureSec: 0.002),
        closeTo(2, 1e-12),
      );
    });

    test('a fine fast drop is a faint line, a heavy slow one fills', () {
      // 0.5 mm at its terminal speed against 3 mm at 2 m/s.
      final fine = RainDrops.streakFill(0.5, RainDrops.terminalSpeed(0.5));
      final heavy = RainDrops.streakFill(3, 2);
      expect(fine, lessThan(0.5));
      expect(heavy, greaterThan(1));
    });

    test('the shutter the alpha is measured at is named and separate', () {
      // Two shutters: the streak's length is drawn at 1/20 s, its transparency
      // at its own.
      expect(RainDrops.exposureSec, 1 / 20);
      expect(RainDrops.alphaExposureSec, 1 / 1375);
      expect(RainDrops.alphaExposureSec, lessThan(RainDrops.exposureSec));
    });
  });

  group('the rain draws that fill', () {
    testWithFlameGame('a drop in focus hides the fill the model gives', (
      game,
    ) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(seed: 3, intensity: 2)..aperture = 0;
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 1);

      final looks = rain.dropLooks.toList();
      expect(looks, isNotEmpty);
      var seen = 0;
      for (final look in looks) {
        if (look.alpha <= 0) {
          continue;
        }
        seen++;
        // In focus the share of the light a drop hides is its fill: the
        // model, with the drop's own size and speed.
        final expected = RainDrops.streakFill(look.diameterMm, look.speed);
        expect(look.alpha, closeTo(expected, 0.01));
      }
      expect(seen, greaterThan(0));
    });

    testWithFlameGame('out of focus a drop shows less of it', (game) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final sharp = Rain(seed: 3, intensity: 2);
      final blurred = Rain(seed: 3, intensity: 2)..aperture = 0.12;
      game.world.addAll([_Ground(), sharp, blurred]);
      await game.ready();
      await _rainFor(game, 1);

      final before = sharp.dropLooks.toList();
      final after = blurred.dropLooks.toList();
      var compared = 0;
      for (var i = 0; i < before.length; i++) {
        final (a, b) = (before[i], after[i]);
        if (a.alpha == 0 || b.alpha == 0) {
          continue;
        }
        // The blurred streak spreads the drop's light over a wider strip, so
        // it shows at less of it.
        expect(b.alpha, lessThanOrEqualTo(a.alpha + 1e-9));
        compared++;
      }
      expect(compared, greaterThan(0));
    });

    testWithFlameGame('the alpha is read as a byte, not as a signed shift', (
      game,
    ) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      // A drop that fills its streak: an alpha over 0.5 reads wrong without
      // the mask (the shift brings a sign in).
      final rain = Rain(seed: 3, intensity: 2)..aperture = 0;
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 1);
      for (final look in rain.dropLooks) {
        expect(look.alpha, inInclusiveRange(0.0, 1.0));
      }
    });

    testWithFlameGame('a drop that fills its streak is opaque, not negative', (
      game,
    ) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      // The share of the light a 2 mm drop hides at its terminal speed: the
      // whole of it, at the alpha's shutter.
      final rain = Rain(seed: 5, intensity: 2);
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 1);
      final alphas = rain.dropLooks.map((l) => l.alpha).where((a) => a > 0);
      expect(alphas, isNotEmpty);
      // Nothing above one, nothing below zero.
      for (final a in alphas) {
        expect(a, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('the light on a drop', () {
    // The same rain, seed for seed, under a sky as bright as [skyLight]
    // (null: no lighting at all), its drops in focus.
    Future<List<double>> alphasUnder(double? skyLight) async {
      final game = await initializeGame(FlameGame.new);
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(seed: 3, intensity: 2)..aperture = 0;
      game.world.addAll([
        _Ground(),
        rain,
        if (skyLight != null) Lighting(skyLight: skyLight, haze: 0),
      ]);
      await game.ready();
      await _rainFor(game, 1);
      final alphas = [for (final look in rain.dropLooks) look.alpha];
      game.onRemove();
      return alphas;
    }

    // Each drop's alpha in [a] over its alpha in [b], for drops whose
    // alpha in [b] is far enough over a byte's step and under one that the
    // ratio is not rounding's or the clamp's.
    List<double> ratios(List<double> a, List<double> b) {
      expect(a.length, b.length);
      return [
        for (var i = 0; i < a.length; i++)
          if (b[i] >= 40 / 255 && b[i] <= 0.99 && a[i] <= 0.99) a[i] / b[i],
      ];
    }

    test('a drop shows as much as the light on it', () async {
      // The same rain under a sky half as bright: each drop hides the same
      // share of what is behind it and throws half the light to the eye -
      // its alpha over the lighting is its fill times the light it scatters.
      final bright = await alphasUnder(0.6);
      final dim = await alphasUnder(0.3);
      final r = ratios(dim, bright);
      expect(r.length, greaterThan(20));
      for (final x in r) {
        expect(x, closeTo(0.5, 0.05));
      }
    });

    test('lit, a drop hides its fill times the light it scatters', () async {
      // Unlit, the alpha is the fill itself; under a sky of 0.6 the eye
      // does not adapt past (its adaptation is 1), so a drop scatters 0.6
      // of the light it would in full light.
      final unlit = await alphasUnder(null);
      final lit = await alphasUnder(0.6);
      final r = ratios(lit, unlit);
      expect(r.length, greaterThan(20));
      for (final x in r) {
        expect(x, closeTo(0.6, 0.05));
      }
    });
  });

  group('a splash keeps its own share', () {
    testWithFlameGame('a droplet in focus hides the droplet share', (
      game,
    ) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(seed: 3, intensity: 2)..aperture = 0;
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 2);
      final alphas = rain.dropletAlphas.toList();
      expect(alphas, isNotEmpty);
      // In focus and unlit every droplet is drawn at the share, as it was
      // drawn before the streaks had a model: 0.9 of a 0.6 colour.
      for (final a in alphas) {
        expect(a, closeTo(Rain.dropletShare, 0.5 / 255));
      }
      expect(Rain.dropletShare, closeTo(0.54, 1e-12));
    });

    testWithFlameGame('out of focus a droplet shows less', (game) async {
      game.camera.viewfinder.anchor = Anchor.topLeft;
      final rain = Rain(seed: 3, intensity: 2)..aperture = 0.12;
      game.world.addAll([_Ground(), rain]);
      await game.ready();
      await _rainFor(game, 2);
      final alphas = rain.dropletAlphas.toList();
      expect(alphas, isNotEmpty);
      for (final a in alphas) {
        expect(a, lessThanOrEqualTo(Rain.dropletShare + 0.5 / 255));
      }
      expect(alphas.where((a) => a < Rain.dropletShare - 2 / 255), isNotEmpty);
    });
  });

  group('the veils draw the same fill', () {
    test("a veil shows its share of a 2 mm drop's fill", () {
      // The veil is made of the same drops as the near ones: it hides the
      // same share of the light behind them, and shows Rain.veilShare of
      // what a drop at the walker's line shows.
      final reference = RainDrops.streakFill(2, RainDrops.terminalSpeed(2));
      expect(Rain.visibility, closeTo(reference, 1e-12));
      expect(Rain.veilShare, closeTo(0.4 / 0.7, 1e-12));
      expect(Rain.visibility * Rain.veilShare, closeTo(0.24, 0.001));
    });
  });
}
