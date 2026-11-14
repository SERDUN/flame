import 'dart:ui';

/// The sky behind the world as it is drawn now: a gradient down the view,
/// [top] at world y [topY] to [horizon] at [horizonY] and the same below it,
/// as the eye sees it - its exposure in it.
///
/// Whatever draws the sky says so here every frame ([set]); whatever
/// mirrors the world shows it where nothing of the world stands across,
/// mirrored as the world is, so water shows the sky that is drawn above it
/// and not a colour of its own.
class SkyView {
  /// Whether anything said what the sky is.
  bool present = false;

  /// World y of the gradient's top and of its horizon.
  double topY = 0;
  double horizonY = 0;

  /// The sky at [topY], and at [horizonY] and below.
  Color top = const Color(0xFF000000);
  Color horizon = const Color(0xFF000000);

  /// The sky this frame.
  void set({
    required double topY,
    required double horizonY,
    required Color top,
    required Color horizon,
  }) {
    present = true;
    this.topY = topY;
    this.horizonY = horizonY;
    this.top = top;
    this.horizon = horizon;
  }

  /// The sky drawn at world y [y]: the top's above [topY], the horizon's
  /// below [horizonY], in between in proportion.
  Color at(double y) {
    final span = horizonY - topY;
    final t = span.abs() < 1e-9 ? 1.0 : ((y - topY) / span).clamp(0.0, 1.0);
    return Color.lerp(top, horizon, t)!;
  }
}
