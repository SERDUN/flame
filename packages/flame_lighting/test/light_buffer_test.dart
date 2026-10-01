import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lamps extends Component with OnStage, LightCarrier {
  _Lamps(this.lights);

  @override
  final List<Light> lights;
}

void main() {
  testWithFlameGame('the buffer gets the strongest lights in view', (
    game,
  ) async {
    game.camera.viewfinder.anchor = Anchor.topLeft;
    final lamps = _Lamps([
      Light.directional(),
      for (var i = 0; i < 20; i++)
        Light.point(offset: Vector2(i * 30.0, 100), intensity: i / 20),
      // Far out of view.
      Light.point(offset: Vector2(5000, 100), intensity: 5),
    ]);
    game.world.add(lamps);
    await game.ready();
    game.update(1 / 60);
    final frame = lamps.stage!.frame;
    final into = Float32List(LightBuffer.floats);
    LightBuffer.write(into, frame, const Rect.fromLTWH(0, 0, 800, 600));
    expect(into.sublist(0, 4), [0, 0, 800, 600]);
    expect(into[9], LightBuffer.maxLights, reason: 'capped, the sky left out');
    // The strongest first: the 20th lamp, 19/20.
    expect(into[12 + 7], closeTo(19 / 20, 1e-6));
    for (var k = 0; k < LightBuffer.maxLights; k++) {
      expect(into[12 + k * LightField.lightFloats], lessThan(1000));
    }
  });

  test('the buffer shader reads the parameters where they are written', () {
    final source = File('gpu_shaders/light_buffer.frag').readAsStringSync();
    expect(
      source,
      contains('const int kMaxLights = ${LightBuffer.maxLights};'),
    );
    expect(
      source,
      contains('const int kMaxShadows = ${LightBuffer.maxShadows};'),
    );
    // view, street, info, then the lights' five vectors and the capsules'
    // two.
    expect(
      RegExp(
        r'uniform Params \{\s*vec4 view;[^}]*vec4 street;[^}]*vec4 info;'
        r'[^}]*vec4 lights\[kMaxLights \* 5\];[^}]*'
        r'vec4 capsules\[kMaxShadows \* 2\];',
      ).hasMatch(source),
      isTrue,
    );
    expect(LightField.lightFloats, 5 * 4);
  });
}
