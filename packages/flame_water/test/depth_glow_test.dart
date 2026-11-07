import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ground from y 400 down: the water is seen at an angle, so its
/// surface lets light out (Fresnel).
class _Road extends Component with OnStage, Ground {
  @override
  Rect groundBand() => const Rect.fromLTWH(0, 400, 800, 200);
}

/// A lighting whose buffer is [image] over the whole view, held [gain]
/// times, its alpha white light or coverage: the GPU buffer's encoding or
/// the canvas path's, made by hand.
class _HeldBuffer extends Lighting {
  _HeldBuffer(this.image, {required this.gain, required this.alphaIsWhite})
    : super(skyLight: 0, glow: 0, haze: 0, lightsBackdrop: false);

  final Image image;
  final double gain;
  final bool alphaIsWhite;

  @override
  Image? get lightImage => image;

  @override
  Rect get lightArea => const Rect.fromLTWH(0, 0, 800, 600);

  @override
  double get lightGain => gain;

  @override
  bool get lightAlphaIsWhite => alphaIsWhite;
}

/// A black night, the world lit in a layer of its own as a game's is, so
/// water is drawn out of the light's multiply.
Lighting _night() =>
    Lighting(skyLight: 0, glow: 0, haze: 0, lightsBackdrop: false);

/// An 800 x 600 image of [color], opaque: a buffer's light.
Image _filled(Color color) {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 800, 600),
    Paint()..color = color,
  );
  return recorder.endRecording().toImageSync(800, 600);
}

/// The rendered game, RGB at a pixel.
Future<(int, int, int) Function(int x, int y)> _render(FlameGame game) async {
  game.update(0);
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(800, 600);
  final bytes = (await image.toByteData())!;
  return (int x, int y) {
    final i = (y * 800 + x) * 4;
    return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  };
}

/// A pond a metre deep from the line 400 down, on a black bed, in a black
/// night; a lamp over it at x 200 (a point, [lamp] strong), or none.
Future<WaterSurface> _pond(
  FlameGame game, {
  required double lampsInDepth,
  double? lamp = 3,
  Lighting? lighting,
}) async {
  await WaterShader.load(asset: 'shaders/water.frag');
  await LightShader.load();
  game.camera.viewfinder.anchor = Anchor.topLeft;
  final water = WaterSurface(
    position: Vector2(0, 400),
    size: Vector2(800, 200),
    shape: WaterShape.rect,
    color: const Color(0xFF000000),
    medium: WaterMedium.pond,
    basinMm: 1000,
    // Nothing to mirror, no smear: the glow of the depth alone.
    fade: 0,
  )..lampsInDepth = lampsInDepth;
  game.world.addAll([
    _Road(),
    water,
    if (lamp != null)
      LightSource(
        position: Vector2(200, 380),
        radius: 400,
        intensity: lamp,
        depth: 0.3,
      ),
    lighting ?? _night(),
  ]);
  await game.ready();
  return water;
}

void main() {
  group('the model', () {
    test('no lamps, or none taken: the sky alone, exactly', () {
      for (final base in [0.0, 0.03, 0.4, 1.0]) {
        expect(DepthGlow.light(base, 0, 1), base);
        expect(DepthGlow.light(base, 2, 0), base);
      }
    });

    test('the lamps fill what the sky leaves, as LightField.fill does', () {
      expect(DepthGlow.light(0.05, 1, 1), LightField.fill(0.05, 1));
      expect(DepthGlow.light(0.05, 1, 1), closeTo(0.6684, 1e-4));
      // Half taken: half the way from the sky's.
      expect(
        DepthGlow.light(0.05, 1, 0.5),
        closeTo((0.05 + LightField.fill(0.05, 1)) / 2, 1e-12),
      );
      // Never past white, however strong.
      expect(DepthGlow.light(0.05, 1e6, 1), lessThanOrEqualTo(1));
    });

    test(
      "a lamp's light on a pond glows in the pond's colour, never as bright",
      () {
        const medium = WaterMedium.pond;
        final deep = medium.deepReflectance;
        // Seen 20 degrees down, a metre deep.
        const s = 0.342;
        final through = medium.transmission(1, s);
        final reflectance = medium.fresnel(s);
        double glowOf(double deep, double through, double lamps) =>
            DepthGlow.glow(
              deep: deep,
              through: through,
              light: DepthGlow.light(0.02, lamps, 1),
              reflectance: reflectance,
            );
        final sky = (
          glowOf(deep.r, through.r, 0),
          glowOf(deep.g, through.g, 0),
          glowOf(deep.b, through.b, 0),
        );
        final lit = (
          glowOf(deep.r, through.r, 2),
          glowOf(deep.g, through.g, 2),
          glowOf(deep.b, through.b, 2),
        );
        // The light falling: 0.02 of the sky's, 0.8727 with the lamp.
        final light = DepthGlow.light(0.02, 2, 1);
        expect(light, closeTo(0.8727, 1e-4));
        expect(
          lit.$2,
          closeTo(deep.g * (1 - through.g) * light * (1 - reflectance), 1e-12),
        );
        expect(lit.$2 / sky.$2, closeTo(light / 0.02, 1e-9));
        // The water's own colour: green over red over blue.
        expect(lit.$2, greaterThan(lit.$1));
        expect(lit.$1, greaterThan(lit.$3));
        // A share of the light falling there, never all of it (#105).
        for (final c in [lit.$1, lit.$2, lit.$3]) {
          expect(c, lessThan(light * 0.1));
        }
      },
    );
  });

  group('the light the depth reads', () {
    testWithFlameGame('taken at night: the lighting buffer of the frame', (
      game,
    ) async {
      final water = await _pond(game, lampsInDepth: 1);
      // The lighting adds the frame's lights up as the frame is drawn.
      await _render(game);
      final lighting = Lighting.of(water)!;
      expect(lighting.lightImage, isNotNull);
      expect(
        DepthGlow.bufferOf(lighting, water.stage!.frame.light, 1),
        same(lighting.lightImage),
      );
    });

    testWithFlameGame('not taken: the sky alone, the buffer not read', (
      game,
    ) async {
      final water = await _pond(game, lampsInDepth: 0);
      await _render(game);
      final lighting = Lighting.of(water)!;
      expect(lighting.lightImage, isNotNull);
      expect(DepthGlow.bufferOf(lighting, water.stage!.frame.light, 0), isNull);
    });

    testWithFlameGame('by day with no lamp on: no buffer, the sky alone', (
      game,
    ) async {
      final water = await _pond(
        game,
        lampsInDepth: 1,
        lamp: null,
        // A day's sky (the default 40 lamps' worth).
        lighting: Lighting(
          glow: 0,
          haze: 0,
          lightsBackdrop: false,
        ),
      );
      await _render(game);
      final lighting = Lighting.of(water)!;
      expect(lighting.lightImage, isNull);
      expect(DepthGlow.bufferOf(lighting, water.stage!.frame.light, 1), isNull);
    });

    test('no lighting, or nothing lit: the sky alone', () {
      expect(DepthGlow.bufferOf(null, LightField(), 1), isNull);
      // A field with no ambience is drawn unlit.
      final unlit = LightField()..begin(null);
      expect(DepthGlow.bufferOf(Lighting(), unlit, 1), isNull);
    });
  });

  group('drawn', () {
    testWithFlameGame(
      'under a lamp the pond glows lighter, in its colour; away from it not',
      (game) async {
        await _pond(game, lampsInDepth: 0);
        final sky = await _render(game);
        game.world.removeAll(game.world.children.toList());
        await game.ready();
        await _pond(game, lampsInDepth: 1);
        final lamps = await _render(game);
        // Below the lamp's mirror, where its light falls on the water.
        final under = lamps(200, 470);
        final before = sky(200, 470);
        expect(under.$2, greaterThan(before.$2 + 2), reason: '$before $under');
        expect(under.$2, greaterThan(under.$1), reason: 'green over red');
        expect(under.$1, greaterThanOrEqualTo(under.$3), reason: 'red, blue');
        // Far past the lamp's reach the night's water as it was.
        expect(lamps(700, 470), sky(700, 470));
      },
    );

    testWithFlameGame('taken with no lamp reaching it: not a level changes', (
      game,
    ) async {
      // A lamp on, so there is a buffer, but nowhere near the water.
      Future<List<(int, int, int)>> rows(double share) async {
        game.world.removeAll(game.world.children.toList());
        await game.ready();
        final water = await _pond(game, lampsInDepth: share, lamp: null);
        game.world.add(
          LightSource(position: Vector2(-4000, 0), radius: 10, intensity: 3),
        );
        await game.ready();
        final at = await _render(game);
        expect(Lighting.of(water)!.lightImage, isNotNull);
        return [
          for (var y = 401; y < 600; y += 7)
            for (var x = 0; x < 800; x += 13) at(x, y),
        ];
      }

      final sky = await rows(0);
      final lamps = await rows(1);
      expect(lamps, sky);
    });

    testWithFlameGame(
      "the GPU buffer's encoding and the canvas path's give the same water",
      (game) async {
        // The same light both ways: 0.4 of colour and 1 of white. The GPU
        // buffer holds it as it is, the white in its alpha; the canvas path's
        // image holds a quarter of it, the white in its colour.
        Future<(int, int, int)> glowWith(Lighting lighting) async {
          game.world.removeAll(game.world.children.toList());
          await game.ready();
          await _pond(game, lampsInDepth: 1, lamp: null, lighting: lighting);
          return (await _render(game))(400, 590);
        }

        const level = 0.4;
        final gpu = await glowWith(
          _HeldBuffer(
            _filled(
              const Color.from(alpha: 1, red: level, green: level, blue: level),
            ),
            gain: 1,
            alphaIsWhite: true,
          ),
        );
        const quarter = (level + 1) / Lighting.canvasGain;
        final canvas = await glowWith(
          _HeldBuffer(
            _filled(
              const Color.from(
                alpha: 1,
                red: quarter,
                green: quarter,
                blue: quarter,
              ),
            ),
            gain: Lighting.canvasGain,
            alphaIsWhite: false,
          ),
        );
        final none = await glowWith(_night());
        expect(
          gpu.$2,
          greaterThan(none.$2 + 2),
          reason: 'it glows: $none $gpu',
        );
        expect((gpu.$1 - canvas.$1).abs(), lessThanOrEqualTo(1));
        expect((gpu.$2 - canvas.$2).abs(), lessThanOrEqualTo(1));
        expect((gpu.$3 - canvas.$3).abs(), lessThanOrEqualTo(1));
      },
    );
  });
}
