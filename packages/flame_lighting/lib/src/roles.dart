import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/light_source.dart';

/// The ground, seen from the side: the band of the view from the line things
/// stand on (its top edge) down towards the viewer. Lights lay pools on it
/// where their cones reach it; rain lands on it at the depth each drop falls
/// at. A scene has one; the systems that need it find it themselves.
mixin Ground on Component {
  /// The band, world coordinates.
  Rect groundBand();

  // How the ground lies before the eye. The band is the ground from the
  // street line (depth 0) to the nearest ground in view (depth 1); these
  // say how far that really is and from how high it is seen, world units,
  // so what depends on the angle of view - how water mirrors, where light
  // falls, how rain scatters it - follows from one place.

  /// How far the nearest ground in view lies in front of the street line.
  double get depthSpan => groundBand().height * 4;

  /// How high above the ground the eye is.
  double get eyeHeight => groundBand().height * 0.65;

  /// How far from the eye the nearest ground in view is.
  double get nearDistance => groundBand().height * 2;

  /// The depth of the ground seen at world [y]: 0 on the street line, 1 the
  /// nearest in view.
  double depthAt(double y) {
    final band = groundBand();
    return ((y - band.top) / band.height).clamp(0.0, 1.0);
  }

  /// The sine of the angle the eye looks down onto the ground at [depth]:
  /// small far off (it looks along the ground), larger near.
  double sinElevation(double depth) {
    final distance = nearDistance + (1 - depth) * depthSpan;
    return eyeHeight / math.sqrt(eyeHeight * eyeHeight + distance * distance);
  }

  /// How much of the light falling on still water at [depth] it mirrors
  /// (Fresnel, Schlick's approximation for water): most of it far off,
  /// where the eye looks along it, little near, where it looks down.
  double waterReflectance(double depth) => fresnel(sinElevation(depth));

  /// Water's reflectance seen at an angle whose sine above the surface is
  /// [sinElevation].
  static double fresnel(double sinElevation) {
    const f0 = 0.02;
    final c = 1 - sinElevation.clamp(0.0, 1.0);
    return f0 + (1 - f0) * c * c * c * c * c;
  }

  /// The ground of the world [component] is in, if there is one.
  static Ground? of(Component component) {
    var top = component;
    for (final a in component.ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top.descendants().whereType<Ground>().firstOrNull;
  }
}

/// Which way a component faces: a character, a car. What it carries - a
/// torch - turns with it.
mixin Facing on Component {
  /// 1 facing its right (+x), -1 its left.
  double get facing;
}

/// A torch in a hand: a narrow cool beam, a little down, the way its holder
/// faces (a [Facing] parent), held at [hold] on the holder - mirrored across
/// it when the holder turns round. Everything else it does is a
/// [LightSource]'s: it cuts the night, lights the rain in its beam, lays a
/// pool on the [Ground] ahead, glints off wet walls and shows in water.
class Torch extends LightSource {
  Torch({
    required this.hold,
    this.tilt = 0.28,
    super.color = const Color(0xFFE6EEFF),
    super.intensity = 0.9,
    super.radius = 380,
    super.coneAngle = 0.62,
    super.sourceRadius = 1.6,
  });

  /// Where it is held on its holder, the holder facing right: in the
  /// holder's own coordinates.
  final Vector2 hold;

  /// How far below level it points, radians.
  final double tilt;

  @override
  void onMount() {
    super.onMount();
    _aim();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _aim();
  }

  void _aim() {
    final holder = parent;
    final facing = holder is Facing && holder.facing < 0 ? -1.0 : 1.0;
    final width = holder is PositionComponent ? holder.size.x : 0.0;
    position.setValues(facing > 0 ? hold.x : width - hold.x, hold.y);
    coneDirection = facing > 0 ? tilt : math.pi - tilt;
  }
}
