import 'dart:io';

import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The float offset each `#define name u[i].c` of [source] names.
Map<String, int> _defines(String source) {
  final define = RegExp(r'#define\s+(\w+)\s+u\[(\d+)\](?:\.(\w))?');
  const components = {
    'x': 0,
    'y': 1,
    'z': 2,
    'w': 3,
    'r': 0,
    'g': 1,
    'b': 2,
    'a': 3,
  };
  return {
    for (final m in define.allMatches(source))
      m[1]!: int.parse(m[2]!) * 4 + (components[m[3]] ?? 0),
  };
}

int _constant(String source, String name) => int.parse(
  RegExp('const int $name = (\\d+);').firstMatch(source)![1]!,
);

void main() {
  final source = File('shaders/light.frag').readAsStringSync();

  test('the Dart offsets are where the shader reads its names', () {
    final defines = _defines(source);
    expect(defines['P_TOP'], LightShader.projectionTop);
    expect(defines['P_BAND'], LightShader.projectionBand);
    expect(defines['P_NEAR'], LightShader.projectionNear);
    expect(defines['P_FAR'], LightShader.projectionFar);
    expect(defines['P_EYE'], LightShader.projectionEye);
    expect(defines['MODE'], LightShader.planeMode);
    expect(defines['AMOUNT'], LightShader.drawAmount);
    expect(defines['WALL_AHEAD'], LightShader.wallAhead);
    expect(defines['FALLOFF'], 18, reason: 'the light carries it');
    expect(defines['S_COUNT'], LightShader.shadowCount);
    // The light block is LightField.writeLight's four vec4.
    expect(defines['L_POS'], 0);
    expect(defines['L_STRENGTH'], 7);
    expect(defines['L_SOURCE'], 15);
    expect(defines['L_SPILL'], 16);
    expect(defines['L_SPILL_RADIUS'], 17);
    expect(LightField.lightFloats, 20);
  });

  test('the arrays are as long on both sides', () {
    expect(_constant(source, 'kShadows'), LightShader.maxShadows);
    expect(_constant(source, 'kCapsules'), LightShader.capsules);
    expect(source, contains('uniform vec4 u[kCapsules + kShadows * 2];'));
    expect(ShadowSet.stride, 2 * 4);
    expect(StreetProjection.uniformFloats, 5);
  });
}
