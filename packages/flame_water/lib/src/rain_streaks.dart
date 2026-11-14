import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_water/src/rain_drops.dart';
import 'package:flame_water/src/rain_pool.dart';
import 'package:flame_water/src/reflection_pass.dart';

/// The rain's drops and droplets as triangles: one draw for all of them.
///
/// Each streak is a strip three vertices wide: full down its middle, clear
/// at its edges - soft-edged as a line drawn smooth, which bare triangles
/// are not. Four triangles, twelve vertices; out of focus, four more fade
/// its ends out over the blur. The buffers are kept and grown, never made
/// anew for a frame.
class RainStreaks {
  Float32List _positions = Float32List(0);
  Int32List _colors = Int32List(0);
  final Paint _paint = Paint();
  int _v = 0;
  int _c = 0;

  /// Draws the drops of [drops] - those listed in [dropRows], or with none
  /// listed every one falling from [from] up to [to] - and likewise the
  /// droplets of [droplets], in their colour [under] the lighting or over
  /// it.
  /// In [mirror] each is mirrored about where it lands, and only those
  /// across from the mirror are drawn.
  void draw(
    Canvas canvas,
    DropPool drops,
    DropletPool droplets, {
    required List<int>? dropRows,
    required List<int>? dropletRows,
    required double from,
    required double to,
    required bool under,
    required Mirror? mirror,
    required double margin,
    required double metre,
  }) {
    final dropCount = dropRows?.length ?? drops.length;
    final dropletCount = dropletRows?.length ?? droplets.length;
    final quads = dropCount + dropletCount;
    if (quads == 0) {
      return;
    }
    if (_positions.length < quads * 48) {
      _positions = Float32List(quads * 48 * 2);
      _colors = Int32List(quads * 24 * 2);
    }
    _v = 0;
    _c = 0;
    // In water, only what stands across from it.
    final area = mirror?.area;
    final left = area?.left ?? double.negativeInfinity;
    final right = area?.right ?? double.infinity;
    final dropColors = under ? drops.colorUnder : drops.color;
    for (var k = 0; k < dropCount; k++) {
      final i = dropRows == null ? k : dropRows[k];
      if (dropRows == null) {
        final depth = drops.depth(i);
        if (depth < from || depth >= to) {
          continue;
        }
      }
      // Its streak trails back along its motion, up to a metre and more.
      final x = drops.x(i);
      if (x < left - margin || x > right + margin) {
        continue;
      }
      final vx = drops.vx(i);
      final vy = drops.vy(i);
      final speed = math.sqrt(vx * vx + vy * vy);
      final length = RainDrops.streakLength(speed / metre) * metre;
      final land = drops.land(i);
      // In water a drop is mirrored about the spot it falls to.
      final shift = mirror?.mirrorShift(land) ?? 0;
      final hy = math.min(drops.y(i), land) + shift;
      final bx = speed < 1e-6 ? 0.0 : vx / speed * length;
      final by = speed < 1e-6 ? 0.0 : vy / speed * length;
      final width = drops.width(i);
      _quad(
        x,
        hy,
        x - bx,
        hy - by,
        width,
        dropColors[i],
        blur: width - drops.sharpWidth(i),
      );
    }
    final dropletColors = under ? droplets.colorUnder : droplets.color;
    for (var k = 0; k < dropletCount; k++) {
      final i = dropletRows == null ? k : dropletRows[k];
      if (dropletRows == null) {
        final depth = droplets.depth(i);
        if (depth < from || depth >= to) {
          continue;
        }
      }
      final x = droplets.x(i);
      if (x < left || x > right) {
        continue;
      }
      final shift = mirror?.mirrorShift(droplets.floor(i)) ?? 0;
      final y = droplets.y(i) + shift;
      final width = droplets.drawnWidth(i);
      _quad(x, y - width / 2, x, y + width / 2, width, dropletColors[i]);
    }
    if (_v == 0) {
      return;
    }
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, _v),
      colors: Int32List.sublistView(_colors, 0, _c),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
  }

  void _point(double x, double y, int argb) {
    _positions[_v++] = x;
    _positions[_v++] = y;
    _colors[_c++] = argb;
  }

  /// A streak from its head ([hx], [hy]) back to its tail ([tx], [ty]),
  /// [w] wide each side, [argb] down its middle; out of focus by [blur],
  /// its ends fade out over that much.
  void _quad(
    double hx,
    double hy,
    double tx,
    double ty,
    double w,
    int argb, {
    double blur = 0,
  }) {
    var nx = ty - hy;
    var ny = hx - tx;
    final len = math.sqrt(nx * nx + ny * ny);
    if (len < 1e-6) {
      nx = w;
      ny = 0;
    } else {
      nx *= w / len;
      ny *= w / len;
    }
    final clear = argb & 0x00FFFFFF;
    if (blur > 1e-6 && len >= 1e-6) {
      // Out of focus the ends are as soft as the sides: each runs out to
      // clear over the blur, past the head and behind the tail.
      final ux = (hx - tx) / len * blur;
      final uy = (hy - ty) / len * blur;
      for (var s = -1.0; s <= 1.0; s += 2) {
        _point(hx + s * nx, hy + s * ny, clear);
        _point(hx, hy, argb);
        _point(hx + ux, hy + uy, clear);
        _point(tx + s * nx, ty + s * ny, clear);
        _point(tx, ty, argb);
        _point(tx - ux, ty - uy, clear);
      }
    }
    // tail edge, tail middle, head middle; tail edge, head middle, head
    // edge - on each side.
    for (var s = -1.0; s <= 1.0; s += 2) {
      _point(tx + s * nx, ty + s * ny, clear);
      _point(tx, ty, argb);
      _point(hx, hy, argb);
      _point(tx + s * nx, ty + s * ny, clear);
      _point(hx, hy, argb);
      _point(hx + s * nx, hy + s * ny, clear);
    }
  }
}
