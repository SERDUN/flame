import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';

/// Something rain bounces off rather than soaks into: an umbrella's canopy,
/// a car roof, a tin awning.
///
/// The rain asks every deflector, for every drop each step, whether the drop
/// met it on its way from where it was to where it is now, at its depth (a
/// deflector stands at a depth of the street and only meets the
/// drops falling there). One that did moves the drop back onto its surface
/// and turns its velocity, and the drop flies on from there; the rain counts
/// the bounce (`Rain.takeBounces`), which is what a game sounds it by. It
/// is on the stage ([OnStage]) for the rain to find it.
mixin RainDeflector on OnStage {
  /// Whether a drop at [depth] that moved from [from] to [to] (world
  /// coordinates) met this; if so, [to] is put back on the surface and
  /// [velocity] (world units per second) turned off it.
  bool deflect(Vector2 from, Vector2 to, Vector2 velocity, double depth);

  /// What a drop meets on it: how a drop bounces off it
  /// ([RainBounce.offDome] with its restitution and slip) and how loud rain
  /// is on it.
  Substance get surface => Substance.canvas;

  /// The depth it stands at, where a drop it turns is heard from
  /// (`Rain.takeImpacts`): a thin thing meets the drops of a slab of depths
  /// round it, but they strike it where it is. `null`: where the drop is.
  double? get standsAtDepth => null;
}

/// How a drop bounces off a curved surface.
abstract final class RainBounce {
  /// A drop that moved from [from] to [to] against a dome: half an ellipse
  /// whose rim is centred at [center], turned by [angle] (radians), rising
  /// [height] along its up (world y down, so towards -y unturned) and
  /// [halfWidth] to each side; [flipped] turns it down, a canopy blown inside
  /// out. [surfaceVelocity] is how the dome moves, so a swinging canopy
  /// throws drops off it. The drop keeps as much of its speed into the
  /// surface, and along it, as [substance] lets it. Returns whether it hit;
  /// then [to] is put back just outside the surface and [velocity]
  /// reflected in place.
  static bool offDome({
    required Vector2 from,
    required Vector2 to,
    required Vector2 velocity,
    required Vector2 center,
    required double angle,
    required double halfWidth,
    required double height,
    Vector2? surfaceVelocity,
    bool flipped = false,
    double margin = 0.02,
    Substance substance = Substance.canvas,
  }) {
    // Almost every drop is nowhere near: rule them out with plain arithmetic
    // before any trigonometry.
    final reach = math.max(halfWidth, height);
    final dx = to.x - center.x;
    final dy = to.y - center.y;
    if (dx * dx + dy * dy > reach * reach) {
      return false;
    }
    final sign = flipped ? -1.0 : 1.0;
    final local = _toLocal(to - center, angle)..y *= sign;
    if (local.y > 0) {
      return false;
    }
    final nx = local.x / halfWidth;
    final ny = local.y / height;
    if (nx * nx + ny * ny > 1) {
      return false;
    }
    final before = _toLocal(from - center, angle)..y *= sign;
    // A drop that came from below the rim entered through the open side: it
    // meets the inside.
    final fromInside = before.y > 0;

    final hw2 = halfWidth * halfWidth;
    final h2 = height * height;
    final localNormal = Vector2(local.x / hw2, local.y / h2)..normalize();
    if (fromInside) {
      localNormal.negate();
    }
    final normal = _toWorld(
      Vector2(localNormal.x, localNormal.y * sign),
      angle,
    );

    final moving = surfaceVelocity ?? Vector2.zero();
    final relative = velocity - moving;
    final into = relative.dot(normal);
    if (into >= 0) {
      return false;
    }
    final normalPart = normal * into;
    final tangentPart = relative - normalPart;
    velocity.setFrom(
      tangentPart * substance.slip -
          normalPart * substance.restitution +
          moving,
    );

    // Back onto the surface, a hair outside, so the next step does not bounce
    // it again.
    final q = math.sqrt(local.x * local.x / hw2 + local.y * local.y / h2);
    final onSurface = q > 1e-6 ? local / q : Vector2(0, -height);
    final pushed = onSurface + localNormal * margin;
    to.setFrom(center + _toWorld(Vector2(pushed.x, pushed.y * sign), angle));
    return true;
  }

  static Vector2 _toLocal(Vector2 v, double angle) {
    final c = math.cos(-angle);
    final s = math.sin(-angle);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  static Vector2 _toWorld(Vector2 v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }
}
