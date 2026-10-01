import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

/// A component that stands in the light's way: a walker, an umbrella, a lamp
/// post, a shelter's roof. Once a frame it tells the stage its shape as a
/// few capsules ([ShadowSet.capsule]) - enough for the light to know what it
/// hides, cheap enough to ask for every drop of rain.
mixin ShadowCaster on Component {
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
    for (var i = 0; i < count; i++) {
      final o = i * stride;
      final cz = data[o + 5];
      final half = data[o + 6] / 2;
      // Where along the way from the light to the point it passes the
      // capsule's depth; light and point both on one side do not pass it.
      final dz = pz - lz;
      double t;
      double distance;
      if (dz.abs() < 1e-6) {
        if ((pz - cz).abs() > half) {
          continue;
        }
        // Light and point at the capsule's depth: the nearest the way from
        // one to the other comes to the capsule.
        final (along, apart) = _segments(lx, ly, px, py, o);
        t = along.clamp(0.02, 0.98);
        distance = apart;
      } else {
        t = (cz - lz) / dz;
        final tHalf = half / dz.abs();
        if (t + tHalf <= 0.02 || t - tHalf >= 0.98) {
          continue;
        }
        t = t.clamp(0.02, 0.98);
        distance = _toSegment(lx + (px - lx) * t, ly + (py - ly) * t, o);
      }
      final radius = data[o + 4];
      // The penumbra: a source of radius s, the occluder at t along the way,
      // blurs the shadow's edge by s(1 - t) / t at the occluder's distance.
      final blur = math.max(source * (1 - t), 1e-3);
      final s = ((distance - radius) / blur + 0.5).clamp(0.0, 1.0);
      final visible = s * s * (3 - 2 * s);
      light *= 1 - data[o + 7] * (1 - visible);
      if (light <= 0.001) {
        return 0;
      }
    }
    return light;
  }

  /// Distance from ([x], [y]) to capsule [o]'s segment.
  double _toSegment(double x, double y, int o) {
    final ax = data[o];
    final ay = data[o + 1];
    final bx = data[o + 2];
    final by = data[o + 3];
    final abx = bx - ax;
    final aby = by - ay;
    final len2 = abx * abx + aby * aby;
    var t = len2 < 1e-9 ? 0.0 : ((x - ax) * abx + (y - ay) * aby) / len2;
    t = t.clamp(0.0, 1.0);
    final dx = x - (ax + abx * t);
    final dy = y - (ay + aby * t);
    return math.sqrt(dx * dx + dy * dy);
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

  /// Writes up to [max] capsules for a shader: two vec4 each, (ax, ay, bx,
  /// by) and (radius, ahead, thickness, opacity), then one vec4 with the
  /// count. Returns the floats written.
  int writeUniforms(Float32List into, int at, {int max = 8}) {
    final n = math.min(count, max);
    var w = at;
    for (var k = 0; k < max; k++) {
      for (var j = 0; j < stride; j++) {
        into[w++] = k < n ? data[k * stride + j] : 0;
      }
    }
    into
      ..[w++] = n.toDouble()
      ..[w++] = 0
      ..[w++] = 0
      ..[w++] = 0;
    return w - at;
  }

  /// Floats [writeUniforms] writes for [max].
  static int uniformFloats(int max) => max * stride + 4;
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
