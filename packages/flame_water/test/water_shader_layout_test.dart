import 'dart:io';

import 'package:flame_water/flame_water.dart';
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
  final source = File('shaders/water.frag').readAsStringSync();

  test('the Dart offsets are where the shader reads its names', () {
    final defines = _defines(source);
    final dart = {
      'uSize': WaterShader.size,
      'uCount': WaterShader.count,
      'uFlatten': WaterShader.flatten,
      'uWavelength': WaterShader.wavelength,
      'uGain': WaterShader.gain,
      'uTime': WaterShader.time,
      'uChop': WaterShader.chop,
      'uElevTop': WaterShader.elevTop,
      'uElevBottom': WaterShader.elevBottom,
      'uFresnel': WaterShader.fresnel,
      'uSpread': WaterShader.spread,
      'uBase': WaterShader.base,
      'uTint': WaterShader.tint,
      'uFade': WaterShader.fade,
      'uLine': WaterShader.line,
      'uPool': WaterShader.pool,
      'uPoolHalf': WaterShader.poolHalf,
      'uSoft': WaterShader.soft,
      'uRound': WaterShader.round,
      'uPixels': WaterShader.pixels,
      'uLightMode': WaterShader.lightMode,
      'uLightCount': WaterShader.lightCount,
      'uHaze': WaterShader.haze,
      'uWave': WaterShader.wave,
      'uGlint': WaterShader.glint,
      'uSquash': WaterShader.squash,
      'uAir': WaterShader.air,
    };
    expect(defines, dart);
  });

  test('the arrays are as long on both sides', () {
    expect(_constant(source, 'kHeader'), WaterShader.header);
    expect(_constant(source, 'kMaxRings'), WaterShader.maxRings);
    expect(_constant(source, 'kMaxLights'), WaterShader.maxLights);
    // Five vectors a light.
    expect(WaterShader.lightFloats, 5 * 4);
    expect(
      WaterShader.floats,
      (WaterShader.header + WaterShader.maxRings + WaterShader.maxLights * 5) *
          4,
    );
    expect(source, contains('uniform vec4 u[kLights + kMaxLights * 5];'));
  });
}
