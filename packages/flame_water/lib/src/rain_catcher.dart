import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';

/// Something rain lands on: water, a road, a roof, a sill, an umbrella.
///
/// The rain asks every catcher on the stage, for every drop, where it would
/// stop the drop; the first one on the drop's way takes it - and of two at
/// the same height the one with the higher [catchOrder] (a puddle over the
/// road it lies on). The catcher then says what the drop does to it. It is
/// on the stage ([OnStage]) for the rain to find it.
mixin RainCatcher on OnStage {
  /// Where a drop falling at [depth] - `0` at the far edge of the ground
  /// (the line things stand on), `1` nearest the viewer, below `0` behind
  /// the street line (over the roofs) - that crossed from
  /// [fromY] to [toY] at [x] this step is stopped, world y; `null` if it is
  /// not caught here.
  double? catchDrop(double x, double fromY, double toY, double depth);

  /// How near the eye its front stands, as a drop's depth; `null` if it
  /// lies along the ground (water, a road). Rain falling nearer the eye
  /// than that passes in front of it: something standing on the street
  /// line (0) - a house - only catches the rain behind that line, on its
  /// roofs and sills.
  double? get frontDepth => null;

  /// Of two catchers stopping a drop at the same height, the higher takes it.
  int get catchOrder => 0;

  /// Whether a drop bursts into droplets where it lands here.
  bool get splashes => true;

  /// A drop landed here at [at] (world), [strength] `0..1` (a heavy drop
  /// against a fine one).
  void onDrop(Vector2 at, double strength) {}
}
