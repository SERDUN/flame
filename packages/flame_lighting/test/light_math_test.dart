import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// One white cone of reach 40 at (32, 20), pointing down, at 0.8, under a
/// night sky.
LightField _field(Falloff falloff) {
  final field = LightField()
    ..beginUnder(sky: const Color(0xFFFFFFFF), skyLight: 0.05);
  field.add(
    Light.cone(
      radius: 40,
      intensity: 0.8,
      color: const Color(0xFFFFFFFF),
      falloff: falloff,
    ),
    32,
    20,
    0,
    0,
    null,
  );
  return field;
}

/// What light.frag draws for the field's light over 64 x 64: its alpha,
/// 0..1, at each pixel.
Future<double Function(int x, int y)> _drawn(
  LightField field, {
  double air = 0,
  double visibility = 1e9,
}) async {
  final shader = LightShader.shader!;
  LightShader.write(
    shader,
    field,
    0,
    plane: LightPlane.wall,
    amount: 1,
    air: air,
    visibility: visibility,
  );
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..shader = shader,
  );
  final image = await recorder.endRecording().toImage(64, 64);
  final bytes = (await image.toByteData())!;
  return (int x, int y) => bytes.getUint8((y * 64 + x) * 4 + 3) / 255;
}

const List<(int, int)> _points = [
  (32, 30),
  (32, 50),
  (40, 44),
  (20, 52),
  (50, 34),
  (32, 21),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => LightShader.load(directory: 'shaders'));

  // The shaders and LightField keep one formula each
  // (shaders/light_math.glsl and its Dart mirrors): they must agree, point
  // by point.
  for (final falloff in Falloff.values) {
    test(
      'the light on a wall is what LightField.reach says (${falloff.name})',
      () async {
        final field = _field(falloff);
        final at = await _drawn(field);
        for (final (x, y) in _points) {
          final expected = field.reach(0, x + 0.5, y + 0.5, 0).clamp(0, 1);
          expect(at(x, y), closeTo(expected, 0.02), reason: '($x, $y)');
        }
      },
    );

    test(
      'the light in the air is what LightField.airLightAt says '
      '(${falloff.name})',
      () async {
        final field = _field(falloff)
          ..airDepth = 30
          ..airVisibility = 60;
        final at = await _drawn(field, air: 30, visibility: 60);
        for (final (x, y) in _points) {
          final expected = field.airLightAt(x + 0.5, y + 0.5).clamp(0, 1);
          expect(at(x, y), closeTo(expected, 0.02), reason: '($x, $y)');
        }
      },
    );
  }

  test("the glow along the eye's way is largest at the light", () {
    expect(
      LightField.glowLength(0, 10),
      greaterThan(LightField.glowLength(3, 10)),
    );
    expect(LightField.glowLength(10, 10), 0);
    expect(
      LightField.glowLength(0, 10, physical: true),
      closeTo(2 * math.atan(4) / 4 * 10, 1e-9),
    );
  });
}
