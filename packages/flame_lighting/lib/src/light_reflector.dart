import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';

/// A surface that mirrors the lights: water, a wet road.
///
/// A lamp in a puddle is the lamp seen in the water, brighter than anything
/// the night lets through: it is drawn over the night, by the `Lighting`,
/// right after the light it casts. The surface draws each light of the
/// frame as it mirrors it - bent by its ripples, smeared by its roughness -
/// from the frame's numbers, not from a picture of the lamp.
mixin LightReflector on OnStage {
  /// Draws the lights of [frame] mirrored in this surface onto [canvas], in
  /// world coordinates, added over the night.
  void renderReflectedLights(Canvas canvas, StageFrame frame);
}
