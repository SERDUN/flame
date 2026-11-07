import 'dart:io';

import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

/// The float offset each `#define name u[i].c` of [source] names; `i` a
/// number, or one of the shader's constants plus a number (`u[kBody + 1]`).
Map<String, int> _defines(String source) {
  final define = RegExp(
    r'#define\s+(\w+)\s+u\[(\w+)(?:\s*\+\s*(\d+))?\](?:\.(\w))?',
  );
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
      m[1]!:
          (_value(source, m[2]!) + int.parse(m[3] ?? '0')) * 4 +
          (components[m[4]] ?? 0),
  };
}

/// A number, or the value of the shader's `const int` [term] names - sums
/// of products of numbers and other constants.
int _value(String source, String term) {
  final number = int.tryParse(term);
  if (number != null) {
    return number;
  }
  final expression = RegExp(
    'const int $term = ([^;]+);',
  ).firstMatch(source)![1]!;
  return expression
      .split('+')
      .map(
        (sum) => sum
            .split('*')
            .map((factor) => _value(source, factor.trim()))
            .reduce((a, b) => a * b),
      )
      .reduce((a, b) => a + b);
}

int _constant(String source, String name) => _value(source, name);

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
      'uPreSmeared': WaterShader.preSmeared,
      'uSquash': WaterShader.squash,
      'uAir': WaterShader.air,
      'uAirMap': WaterShader.airMap,
      'uImage': WaterShader.image,
      'uSkyTop': WaterShader.skyTop,
      'uSkyHorizon': WaterShader.skyHorizon,
      'uSkyY': WaterShader.skyY,
      'uAtten': WaterShader.attenuation,
      'uDeep': WaterShader.deep,
      'uAmbient': WaterShader.ambient,
      'uHoleInfo': WaterShader.holeCount,
      'uLampArea': WaterShader.lampArea,
      'uLampInfo': WaterShader.lampInfo,
      'uSilt': WaterShader.silt,
    };
    expect(defines, dart);
  });

  test('the arrays are as long on both sides', () {
    expect(_constant(source, 'kHeader'), WaterShader.header);
    expect(_constant(source, 'kMaxRings'), WaterShader.maxRings);
    expect(_constant(source, 'kMaxLights'), WaterShader.maxLights);
    // Six vectors a light.
    expect(WaterShader.lightFloats, 6 * 4);
    // Three vectors after the holes: the light the depth glows by and the
    // layer on the water.
    expect(
      WaterShader.floats,
      (WaterShader.header +
              WaterShader.maxRings +
              WaterShader.maxLights * 6 +
              WaterShader.maxHoles +
              3) *
          4,
    );
    expect(_constant(source, 'kMaxHoles'), WaterShader.maxHoles);
    expect(_constant(source, 'kHoles') * 4, WaterShader.holes);
    expect(_constant(source, 'kBody') * 4, WaterShader.body);
    expect(source, contains('uniform vec4 u[kBody + 3];'));
  });
}
