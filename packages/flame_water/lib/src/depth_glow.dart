import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';

/// The glow of a water's depth: what deep water sends back up of the light
/// falling on it (its medium's `WaterMedium.deepReflectance`), from as much
/// of it as there is above the bottom, through its surface.
///
/// The light falling on it is the sky's, as the eye takes it, and - where
/// the water takes them ([WaterSurface.lampsInDepth]) - the lamps' at each
/// point, as the lighting's light buffer has them, filled in over the sky's
/// by the one curve the rest of the light takes ([LightField.fill], drawn by
/// the compose shader). So a lamp's light that falls on the water goes into
/// it, is scattered back in its depth and comes out in the water's own
/// colour; between the lamps it is the sky's alone, and it is never brighter
/// than the light falling there.
///
/// The water shader (`water.frag`, its `body`) works it out per pixel; this
/// is the same in Dart, for the tests and for whatever decides which light
/// the shader reads ([bufferOf]).
abstract final class DepthGlow {
  /// The light falling on the water, one channel, as the eye takes it: the
  /// sky's [base] (`0..1`) and the lamps' [lamps] more (exposed, in the
  /// buffer's units), [share] of the lamps' taken. With no lamps, or a share
  /// of 0, exactly [base].
  static double light(double base, double lamps, double share) {
    if (share <= 0 || lamps <= 0) {
      return base;
    }
    final seen = LightField.fill(base, lamps);
    return base + (seen - base) * share.clamp(0.0, 1.0);
  }

  /// The glow of the depth, one channel: what deep water sends back
  /// ([deep]) of the light falling on it ([light]), from the share of it
  /// above the bottom (`1 - through`), out through its surface (`1 -
  /// reflectance`), as much as there is water ([cover]).
  static double glow({
    required double deep,
    required double through,
    required double light,
    required double reflectance,
    double cover = 1,
  }) => deep * (1 - through) * light * (1 - reflectance) * cover;

  /// The light buffer the glow of a water's depth reads: the lighting's
  /// buffer of this frame ([Lighting.lightImage]) when the water takes the
  /// lamps' light ([share] above 0) and the lighting has one - none by day,
  /// with no light on, or with nothing lit at all. `null`: the sky's light
  /// alone, as one figure for the whole surface, and the buffer is not read.
  static Image? bufferOf(Lighting? lighting, LightField? field, double share) {
    if (share <= 0 || lighting == null || field == null || !field.isLit) {
      return null;
    }
    return lighting.lightImage;
  }

  /// The factor the shader takes the buffer's texels by: the eye's
  /// [exposure] times how many times its value the image holds ([gain]),
  /// as the compose shader takes them.
  static double texelScale(double exposure, double gain) =>
      math.max(exposure, 0) * gain;
}
