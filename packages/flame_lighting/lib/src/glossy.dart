import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/lighting.dart';

/// A wet surface that is no mirror: a wall, a roof, a car's side in the rain.
///
/// Wet, it is darker ([darkening]). Rough and upright, it does not show the
/// street, but the light that falls on it glints off the water on it: a
/// sheen of every light over [glossArea], as strong as [gloss] - shadows
/// and all - and faint damp trails where water runs down it, seen only where
/// light falls. It is drawn right after the component, so it lies where the
/// component is: behind what stands in front of it.
mixin Glossy on Component {
  /// Draws the component, then its darkening and the lighting's sheen over
  /// it. Nothing to call by hand.
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
