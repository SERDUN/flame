import 'dart:ui';

import 'package:flame/components.dart';

/// A surface that shows the lights above it mirrored: water, a wet road, a
/// glossy roof. The `Lighting` layer lights it where a mirrored light falls,
/// drawn out down the surface as light on wet ground is.
mixin LightMirror on Component {
  /// World y of the line the lights are mirrored about.
  double get mirrorLine;

  /// How tall a reflection is against what it reflects (as the surface's
  /// own mirror): below 1 squeezes it.
  double get mirrorSquash;

  /// How much light it gives back, `0..1`.
  double get mirrorStrength;

  /// How far a light's reflection is drawn out down the surface, against its
  /// width: 1 a round spot (still water), more a long streak (a wet road).
  double get mirrorStretch;

  /// Where it shows reflections, world coordinates.
  Path mirrorClip();

  /// How far the surface's own movement (ripples from drops) shifts what it
  /// mirrors at ([x], [y]), world coordinates and units; zero on still
  /// water. The lights' reflections move with it, so a ring passing through
  /// a lamp's streak breaks and bends it.
  Offset disturbanceAt(double x, double y) => Offset.zero;
}
