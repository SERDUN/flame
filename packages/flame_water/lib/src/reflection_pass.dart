import 'package:flame/components.dart';
import 'package:flame_water/src/water_surface.dart';

/// Marks a component as part of what water reflects.
///
/// A [WaterSurface] mirrors the world above it, but only the components with
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

/// The reflection being drawn right now, if any.
///
/// While a [WaterSurface] draws the world mirrored in it, [current] is that
/// surface: a component may skip fine detail in a reflection, or draw a
/// different look (a lamp's glow instead of its bulb, for example).
abstract final class ReflectionPass {
  static WaterSurface? _current;

  /// The surface drawing its reflection now; `null` outside a reflection.
  static WaterSurface? get current => _current;

  /// Whether the component being drawn is a reflection.
  static bool get isActive => _current != null;

  /// Runs [draw] as the reflection in [surface]; passes do not nest (water is
  /// not reflected in water).
  static void run(WaterSurface surface, void Function() draw) {
    if (_current != null) {
      return;
    }
    _current = surface;
    try {
      draw();
    } finally {
      _current = null;
    }
  }
}
