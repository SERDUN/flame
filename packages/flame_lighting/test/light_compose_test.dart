import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_lighting/flame_lighting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A light buffer 256 x 1: red rising 0..1 across it, the rest 0, opaque
/// (alpha is white light, 1 everywhere).
Future<Image> _ramp() async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  for (var x = 0; x < 256; x++) {
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), 0, 1, 1),
      Paint()..color = Color.fromARGB(255, x, 0, 0),
    );
  }
  return recorder.endRecording().toImage(256, 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the lamps fill what the sky leaves up to white smoothly, '
      'never at a hard stop', () async {
    await LightShader.load(directory: 'shaders');
    final ramp = await _ramp();
    // Exposed four times over: lit far past white, where a clamp would
    // flatten the top of the ramp to one value.
    const expose = 4.0;
    final shader = LightShader.compose!
      ..setFloat(0, 0)
      ..setFloat(1, 0)
      ..setFloat(2, 256)
      ..setFloat(3, 1)
      ..setFloat(4, 0)
      ..setFloat(5, 0)
      ..setFloat(6, 0)
      ..setFloat(7, expose)
      ..setFloat(8, 0)
      ..setFloat(9, 0)
      ..setFloat(10, 0)
      ..setFloat(11, 0)
      ..setImageSampler(0, ramp);
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 256, 1),
      Paint()..shader = shader,
    );
    final image = await recorder.endRecording().toImage(256, 1);
    final bytes = (await image.toByteData())!;
    int red(int x) => bytes.getUint8(x * 4);
    // With no sky, the lamps' light l comes out as 1 - e^-l.
    for (final x in const [0, 64, 128, 192]) {
      final lamps = (x / 255 + 1) * expose;
      expect(red(x), closeTo(255 * (1 - math.exp(-lamps)), 3), reason: 'x $x');
    }
    // Still rising where a clamp would long have stopped (it stopped at a
    // light of 1, here everywhere).
    expect(red(64), lessThan(red(255)));
  });
}
