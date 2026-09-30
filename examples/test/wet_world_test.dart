import 'dart:io';
import 'dart:ui';

import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Renders the rainy night for a while: the whole wet world runs without
  // an error. With WET_WORLD_FRAME=<path> the last frame is saved to look at,
  // at WET_WORLD_SECONDS.
  testWithGame<RainyNightExample>(
    'the rainy night renders',
    RainyNightExample.new,
    (game) async {
      game.onGameResize(Vector2(800, 450));
      // WET_WORLD_SECONDS picks the moment to look at (3 s by default).
      final seconds =
          double.tryParse(Platform.environment['WET_WORLD_SECONDS'] ?? '') ?? 3;
      for (var i = 0; i < seconds * 30; i++) {
        game.update(1 / 30);
      }
      final recorder = PictureRecorder();
      game.render(Canvas(recorder));
      final image = await recorder.endRecording().toImage(800, 450);
      final path = Platform.environment['WET_WORLD_FRAME'];
      if (path != null) {
        final png = await image.toByteData(format: ImageByteFormat.png);
        File(path).writeAsBytesSync(png!.buffer.asUint8List());
      }
      expect(image.width, 800);
    },
  );
}
