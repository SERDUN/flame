import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Rings spreading from where drops hit the water, seen from the side: each
/// is an ellipse flattened by [flatten], growing to [maxRadius] over [lifeSec]
/// while it fades.
///
/// A fixed pool: when it is full the oldest ring gives way, so a downpour
/// costs no more than a drizzle. Positions are in the surface's own
/// coordinates.
class RippleRings {
  RippleRings({
    this.capacity = 48,
    this.lifeSec = 0.7,
    this.maxRadius = 24,
    this.flatten = 0.25,
  }) : _x = Float64List(capacity),
       _y = Float64List(capacity),
       _age = Float64List(capacity)..fillRange(0, capacity, double.infinity),
       _strength = Float64List(capacity);

  /// Rings alive at once, at most.
  final int capacity;

  /// Seconds a ring spreads and fades.
  final double lifeSec;

  /// Radius a ring reaches, across the water.
  final double maxRadius;

  /// Height of a ring over its width: water seen at a low angle.
  final double flatten;

  final Float64List _x;
  final Float64List _y;
  final Float64List _age;
  final Float64List _strength;
  int _next = 0;

  /// Rings alive now.
  int get count {
    var n = 0;
    for (var i = 0; i < capacity; i++) {
      if (_age[i] < lifeSec) {
        n++;
      }
    }
    return n;
  }

  /// Starts a ring at ([x], [y]); [strength] (`0..1`) scales how big and how
  /// bright it gets - a heavy drop against a fine one.
  void add(double x, double y, {double strength = 1}) {
    _x[_next] = x;
    _y[_next] = y;
    _age[_next] = 0;
    _strength[_next] = strength.clamp(0.0, 1.0);
    _next = (_next + 1) % capacity;
  }

  void update(double dt) {
    for (var i = 0; i < capacity; i++) {
      if (_age[i] < lifeSec) {
        _age[i] += dt;
      }
    }
  }

  /// Radius of ring [i] and its opacity (`0..1`), or `null` once it is gone.
  (double radius, double opacity)? ring(int i) {
    final age = _age[i];
    if (age >= lifeSec) {
      return null;
    }
    final t = age / lifeSec;
    // Quick at first, then slowing, as a ring on water does.
    final grow = 1 - math.pow(1 - t, 2).toDouble();
    final strength = _strength[i];
    return (maxRadius * grow * (0.5 + 0.5 * strength), (1 - t) * strength);
  }

  /// Draws every live ring with [paint] (a stroke), its opacity scaled by each
  /// ring's.
  void render(Canvas canvas, Paint paint) {
    final alpha = paint.color.a;
    for (var i = 0; i < capacity; i++) {
      final r = ring(i);
      if (r == null) {
        continue;
      }
      final (radius, opacity) = r;
      paint.color = paint.color.withValues(alpha: alpha * opacity);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(_x[i], _y[i]),
          width: radius * 2,
          height: radius * 2 * flatten,
        ),
        paint,
      );
    }
    paint.color = paint.color.withValues(alpha: alpha);
  }
}
