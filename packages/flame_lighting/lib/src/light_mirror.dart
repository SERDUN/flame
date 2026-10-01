import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/lighting.dart';

/// Parts of a component that give light themselves: a bulb, a lit window,
/// the halo wet air makes round a lamp.
///
/// The component draws them in place, as part of its own render (so what
/// stands in front of it hides them), and the `Lighting` hands them to every
/// [LightMirror], which shows them mirrored as it mirrors anything.
mixin Emissive on Component {
  /// Draws the glowing parts, in this component's own coordinates. Call it
  /// from the component's render too.
  void renderEmissive(Canvas canvas);
}

/// A surface that mirrors light: water, a wet road, a glossy roof.
///
/// A lamp in a puddle is the lamp's own glow seen in the water, so it has to
/// go through whatever the surface does to a reflection - ripples bend it,
/// a rough wet road smears it into a long streak. The lighting gives each
/// mirror the world's glow to draw that way.
mixin LightMirror on Component {
  /// Draws the world's glow mirrored in this surface onto [canvas], which is
  /// in world coordinates. [glow] draws every [Emissive] part of the world,
  /// in world coordinates, onto the canvas it is given.
  ///
  /// A light's source is brighter than an image's white; the light its haze
  /// scatters is not. A mirror that gives what it is given back `headroom`
  /// times brighter passes that number to [glow], which then draws what the
  /// air scatters that much fainter: brought back, only the sources come out
  /// brighter than white, and a halo as bright as it is.
  void renderMirroredGlow(
    Canvas canvas,
    void Function(Canvas canvas, double headroom) glow,
  );
}

/// A wet surface that is no mirror: a wall, a roof, a car's side in the rain.
///
/// Wet, it is darker ([darkening]). Rough and upright, it does not show the
/// street, but the light that falls on it glints off the water on it: a
/// sheen of every light over [glossArea], as strong as [gloss], and faint
/// damp trails where water runs down it, seen only where light falls. It is
/// drawn right after the component, so it lies where the component is -
/// behind what stands in front of it.
mixin Glossy on Component {
  /// Draws the component, then the sheen of the world's `Lighting` (if it
  /// has one) over it - right after it, so the sheen lies where it is and
  /// whatever stands in front of it hides it. Nothing to call by hand.
  @override
  void renderTree(Canvas canvas) {
    super.renderTree(canvas);
    final dark = darkening.clamp(0.0, 1.0);
    final lighting = Lighting.of(this);
    if (lighting == null && dark <= 0) {
      return;
    }
    // After its own tree the canvas is back in its parent's coordinates;
    // the sheen is laid out in the world's.
    canvas.save();
    final holder = parent;
    if (holder is PositionComponent) {
      final origin = holder.absoluteTopLeftPosition;
      canvas.translate(-origin.x, -origin.y);
    }
    if (dark > 0) {
      // Darker where wet, under whatever light then falls on it.
      canvas.drawPath(
        glossArea(),
        _darken..color = Color.fromRGBO(0, 0, 0, dark),
      );
    }
    lighting?.drawSheen(canvas, this);
    canvas.restore();
  }

  static final Paint _darken = Paint();

  /// How much of its colour it has lost to the water in it, `0..1`: a wet
  /// wall is darker than a dry one. Drawn over [glossArea].
  double get darkening => 0;

  /// How wet and glossy it is, `0..1`: 0 dry, 1 streaming.
  double get gloss;

  /// Where it is wet, world coordinates.
  Path glossArea();

  /// Rivulets per 100 world units across it.
  double get rivulets => 9;
}
