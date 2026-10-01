import 'dart:ui';

import 'package:flame/components.dart';

/// Marks a component as part of what water reflects.
///
/// Water mirrors the world above it, but only the components with
/// this mixin (and everything under them) take part: the scenery, the
/// characters, the lights - not the HUD, not debug overlays, not the water
/// itself. A component can still tell it is being drawn as a reflection
/// through [ReflectionPass.isActive], and draw itself more simply there.
mixin Reflectable on Component {
  /// World y of the line where it meets the ground, if not the water's
  /// line: seen from the side, something standing nearer the eye stands
  /// lower in the view, and water mirrors it about where it stands. `null`:
  /// it stands on the line the water mirrors about.
  double? get reflectionBase => null;

  /// How far in front of the street line it stands, as a depth of the
  /// world's `Ground` (below 0 behind it); `null`: on the line. Water mirrors
  /// it about where that depth meets the ground - unless [reflectionBase]
  /// says outright.
  double? get groundDepth => null;
}

/// What a reflection is drawn for: water mirroring the world, or many
/// waters at once.
abstract interface class Mirror {
  /// How far to move something (world units, down) for the mirror about
  /// the water line to show it mirrored about [base] instead - the line it
  /// stands on, or a drop the spot it falls to.
  double mirrorShift(double base);

  /// What of the world it can show, world coordinates: its mirror is
  /// upright, so only what stands across from it, give or take how far its
  /// ripples and roughness move what it mirrors.
  Rect get area;

  /// The component the reflection is drawn into: whatever looks different
  /// over the night and under it goes by where this one is.
  Component get drawer;
}

/// The reflection being drawn right now, if any.
///
/// While water draws the world mirrored in it, [current] is that mirror: a
/// component may skip fine detail in a reflection, or draw a different look
/// (a lamp's glow instead of its bulb, for example).
abstract final class ReflectionPass {
  static Mirror? _current;

  /// The mirror being drawn now; `null` outside a reflection.
  static Mirror? get current => _current;

  /// Whether the component being drawn is a reflection.
  static bool get isActive => _current != null;

  /// What of the world the mirror drawing now can show, world coordinates.
  /// A component drawing many things (a layer of decor, the rain) may draw
  /// only those across this; `null` outside a reflection.
  static Rect? get area => _current?.area;

  /// Runs [draw] as the reflection in [mirror]; passes do not nest (water
  /// is not reflected in water).
  static void run(Mirror mirror, void Function() draw) {
    if (_current != null) {
      return;
    }
    _current = mirror;
    try {
      draw();
    } finally {
      _current = null;
    }
  }
}
