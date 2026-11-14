import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flame_stage/src/stage.dart';

/// A component that stands in the light's way: a walker, an umbrella, a lamp
/// post, a shelter's roof. Once a frame it tells the stage its shape as a
/// few capsules ([ShadowSet.capsule]) - enough for the light to know what it
/// hides, cheap enough to ask for every drop of rain.
mixin ShadowCaster on OnStage {
  /// Writes its shape now into [shadows], world coordinates.
  void castShadow(ShadowSet shadows);
}

/// What stands in the light's way this frame: capsules - a segment with a
/// radius round it - each at a street depth, as flat data.
///
/// A capsule is thin in depth: it is a slice of a body at the depth the body
/// stands at, [ShadowSet.capsule]'s `thickness` deep. Light passing that
/// depth inside the capsule is blocked; near its edge it is blocked in part,
/// over a penumbra as wide as the light's source makes it.
class ShadowSet {
  /// Floats per capsule.
  static const int stride = 8;

  Float32List data = Float32List(stride * 16);

  /// Capsules in [data].
  int count = 0;

  /// Starts a frame over: nothing in the way.
  void clear() => count = 0;

  /// Puts the capsules nearest world ([x], [y]) first, so a shader that takes
  /// only so many takes the ones in the middle of the view: the walker before
  /// a fence at its edge.
  void nearestFirst(double x, double y) {
    if (count < 2) {
      return;
    }
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => _distance2(a, x, y).compareTo(_distance2(b, x, y)));
    final sorted = Float32List(data.length);
    for (var k = 0; k < count; k++) {
      sorted.setRange(
        k * stride,
        (k + 1) * stride,
        data,
        order[k] * stride,
      );
    }
    data = sorted;
  }

  // Squared distance from world (x, y) to capsule i's middle.
  double _distance2(int i, double x, double y) {
    final o = i * stride;
    final dx = (data[o] + data[o + 2]) / 2 - x;
    final dy = (data[o + 1] + data[o + 3]) / 2 - y;
    return dx * dx + dy * dy;
  }

  /// Adds a capsule from ([ax], [ay]) to ([bx], [by]), world coordinates,
  /// [radius] round it, standing [ahead] world units in front of the street
  /// line and [thickness] deep there; [opacity] of the light it stops,
  /// `0..1` (a canopy all, rain-soaked cloth less).
  void capsule(
    double ax,
    double ay,
    double bx,
    double by, {
    required double radius,
    double ahead = 0,
    double thickness = 0,
    double opacity = 1,
  }) {
    if ((count + 1) * stride > data.length) {
      data = Float32List(data.length * 2)..setAll(0, data);
    }
    final o = count * stride;
    data
      ..[o] = ax
      ..[o + 1] = ay
      ..[o + 2] = bx
      ..[o + 3] = by
      ..[o + 4] = radius
      ..[o + 5] = ahead
      ..[o + 6] = math.max(thickness, radius)
      ..[o + 7] = opacity.clamp(0.0, 1.0);
    count++;
  }

  /// How much light gets through from a source at ([lx], [ly], [lz]) with a
  /// [source] radius to the point ([px], [py], [pz]) - x, y on screen, z
  /// world units in front of the street line - past everything in the way,
  /// `0..1`: 0 in full shadow, between in the penumbra.
  double through(
    double lx,
    double ly,
    double lz,
    double px,
    double py,
    double pz,
    double source,
  ) {
    var light = 1.0;
    final ex = px - lx;
    final ey = py - ly;
    final ez = pz - lz;
    final length = math.sqrt(ex * ex + ey * ey + ez * ez);
    for (var i = 0; i < count; i++) {
      final o = i * stride;
      final cz = data[o + 5];
      final half = data[o + 6] / 2;
      final radius = data[o + 4];
      // How near either end of the way an occluder may be and still count,
      // as a share of the way: a capsule's radius - on a lamp's short way
      // no nearer than 2 %, on the sun's long one a body's width.
      final end = math.min(0.02, radius / math.max(length, 1e-9));
      // The part of the way from the light to the point that runs through
      // the capsule's depth, kept off both ends; then the nearest that part
      // comes to the capsule on screen. Taken from the point back, so the
      // sun's far-off light keeps its precision.
      double t0;
      double t1;
      if (ez.abs() < 1e-9) {
        if ((lz - cz).abs() > half) {
          continue;
        }
        t0 = 0;
        t1 = 1;
      } else {
        final ta = (cz - half - lz) / ez;
        final tb = (cz + half - lz) / ez;
        t0 = math.min(ta, tb);
        t1 = math.max(ta, tb);
      }
      t0 = math.max(t0, end);
      t1 = math.min(t1, 1 - end);
      if (t0 >= t1) {
        continue;
      }
      final (along, distance) = _segments(
        px - ex * (1 - t0),
        py - ey * (1 - t0),
        px - ex * (1 - t1),
        py - ey * (1 - t1),
        o,
      );
      final t = t0 + (t1 - t0) * along;
      // The penumbra: a source of radius s, the occluder at t along the way,
      // blurs the shadow's edge by s(1 - t) / t at the occluder's distance.
      final blur = math.max(source * (1 - t), radius * 1e-3);
      final s = ((distance - radius) / blur + 0.5).clamp(0.0, 1.0);
      final visible = s * s * (3 - 2 * s);
      light *= 1 - data[o + 7] * (1 - visible);
      if (light <= 0.001) {
        return 0;
      }
    }
    return light;
  }

  /// The nearest the segment from (px1, py1) to (px2, py2) comes to
  /// capsule [o]'s segment: where along the first it is, `0..1`, and how
  /// far apart they are there.
  (double, double) _segments(
    double px1,
    double py1,
    double px2,
    double py2,
    int o,
  ) {
    final qx1 = data[o];
    final qy1 = data[o + 1];
    final d1x = px2 - px1;
    final d1y = py2 - py1;
    final d2x = data[o + 2] - qx1;
    final d2y = data[o + 3] - qy1;
    final rx = px1 - qx1;
    final ry = py1 - qy1;
    final a = d1x * d1x + d1y * d1y;
    final e = d2x * d2x + d2y * d2y;
    final f = d2x * rx + d2y * ry;
    double s;
    double t;
    if (a <= 1e-12 && e <= 1e-12) {
      s = 0;
      t = 0;
    } else if (a <= 1e-12) {
      s = 0;
      t = (f / e).clamp(0.0, 1.0);
    } else {
      final c = d1x * rx + d1y * ry;
      if (e <= 1e-12) {
        t = 0;
        s = (-c / a).clamp(0.0, 1.0);
      } else {
        final b = d1x * d2x + d1y * d2y;
        final denom = a * e - b * b;
        s = denom > 1e-12 ? ((b * f - c * e) / denom).clamp(0.0, 1.0) : 0.0;
        t = (b * s + f) / e;
        if (t < 0) {
          t = 0;
          s = (-c / a).clamp(0.0, 1.0);
        } else if (t > 1) {
          t = 1;
          s = ((b - c) / a).clamp(0.0, 1.0);
        }
      }
    }
    final dx = px1 + d1x * s - (qx1 + d2x * t);
    final dy = py1 + d1y * s - (qy1 + d2y * t);
    return (s, math.sqrt(dx * dx + dy * dy));
  }

  // Read back, for drawing shadows.
  double axOf(int i) => data[i * stride];
  double ayOf(int i) => data[i * stride + 1];
  double bxOf(int i) => data[i * stride + 2];
  double byOf(int i) => data[i * stride + 3];
  double radiusOf(int i) => data[i * stride + 4];
  double aheadOf(int i) => data[i * stride + 5];
  double opacityOf(int i) => data[i * stride + 7];
}

/// Writes a capsule for a [PositionComponent] standing upright at its
/// anchor: what a simple caster (a post, a figure) tells the stage.
extension UprightShadow on ShadowSet {
  /// An upright capsule [height] tall and [width] wide standing on the
  /// ground at world [foot], [ahead] in front of the street line.
  void upright(
    Vector2 foot, {
    required double height,
    required double width,
    double ahead = 0,
    double opacity = 1,
  }) => capsule(
    foot.x,
    foot.y - width / 2,
    foot.x,
    foot.y - height + width / 2,
    radius: width / 2,
    ahead: ahead,
    thickness: width,
    opacity: opacity,
  );
}
