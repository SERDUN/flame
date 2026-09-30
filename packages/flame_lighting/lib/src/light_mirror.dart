import 'dart:ui';

import 'package:flame/components.dart';

/// Parts of a component that give light themselves: a bulb, a lit window,
/// the halo wet air makes round a lamp.
///
/// The `Lighting` draws them over the night, undimmed, after it has cut the
/// lights out of the dark - and hands them to every [LightMirror], which
/// shows them mirrored as it mirrors anything.
mixin Emissive on Component {
  /// Draws the glowing parts, in this component's own coordinates.
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
  void renderMirroredGlow(Canvas canvas, void Function(Canvas canvas) glow);
}

/// A wet surface that is no mirror: a wall, a roof, a car's side in the rain.
///
/// Rough and upright, it does not show the street, but the light that falls
/// on it glints off the water on it: the `Lighting` lays a sheen of every
/// light over [glossArea], as strong as [gloss], and faint damp trails where
/// water runs down it, seen only where light falls.
mixin Glossy on Component {
  /// How wet and glossy it is, `0..1`: 0 dry, 1 streaming.
  double get gloss;

  /// Where it is wet, world coordinates.
  Path glossArea();

  /// Rivulets per 100 world units across it.
  double get rivulets => 9;
}
