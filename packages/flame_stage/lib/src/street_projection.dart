import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

@immutable
/// How the eye stands before a street, in heights of the ground band seen:
/// how far in front of the street line the nearest ground in view lies,
/// how far the eye is from that nearest ground, and how high above the
/// ground it is.
class DepthCamera {
  const DepthCamera({
    this.spanPerBand = 4,
    this.nearPerBand = 2,
    this.eyePerBand = 0.65,
  });

  /// The usual street: the nearest ground in view four band heights in
  /// front of the line, two from the eye, the eye at 0.65 of a band up.
  static const DepthCamera street = DepthCamera();

  /// How far in front of the street line the nearest ground in view lies.
  final double spanPerBand;

  /// How far from the eye the nearest ground in view is.
  final double nearPerBand;

  /// How high above the ground the eye is.
  final double eyePerBand;

  @override
  bool operator ==(Object other) =>
      other is DepthCamera &&
      other.spanPerBand == spanPerBand &&
      other.nearPerBand == nearPerBand &&
      other.eyePerBand == eyePerBand;

  @override
  int get hashCode => Object.hash(spanPerBand, nearPerBand, eyePerBand);
}

@immutable
/// The one depth projection of a side-view street, as it is in one frame.
///
/// Everything in the scene stands at a depth: below 0 behind the street line
/// (far houses, roofs, rain over them), 0 on it (the walker, what lines the
/// street), 0..1 on the ground in front of it, down to the nearest ground in
/// view (puddles, near things, near rain). From the depth follow where a
/// thing meets the ground on screen ([yAt]), how big it is and how fast it
/// slides by as the view moves ([scaleAt], [projectX]), how far in front of
/// the line it really is ([ahead]) and the angle the eye looks down at it
/// ([sinElevation]): how water there mirrors, where light falls, how rain
/// scatters it.
///
/// The band is laid out as a perspective view lays out a ground: its rows
/// are equal steps of 1 / distance, so they crowd towards the street line.
/// Depth is that step: linear on the screen, not in distance.
///
/// A value: made once a frame from the band the scene's `Ground` gives, and
/// asked freely after - no call goes back to the camera or the tree.
class StreetProjection {
  StreetProjection(this.band, {this.camera = DepthCamera.street})
    : span = band.height * camera.spanPerBand,
      eyeHeight = band.height * camera.eyePerBand,
      nearDistance = band.height * camera.nearPerBand,
      farDistance = band.height * (camera.nearPerBand + camera.spanPerBand);

  /// The ground band, world coordinates: its top edge is the street line.
  final Rect band;

  /// How the eye stands before it.
  final DepthCamera camera;

  /// How far in front of the street line the nearest ground in view lies,
  /// world units.
  final double span;

  /// How high above the ground the eye is.
  final double eyeHeight;

  /// How far from the eye the nearest ground in view is.
  final double nearDistance;

  /// How far from the eye the street line is.
  final double farDistance;

  /// World y of the street line.
  double get line => band.top;

  /// How far from the eye something at [depth] is: the street line at 0,
  /// the nearest ground in view at 1; behind the line, farther.
  double distanceAt(double depth) {
    final step = 1 / nearDistance - 1 / farDistance;
    // Far behind the line the distance runs to the horizon; keep it finite.
    final inverse = math.max(
      1 / farDistance + depth * step,
      0.05 / farDistance,
    );
    return 1 / inverse;
  }

  /// The depth at which something [distance] from the eye stands: the
  /// inverse of [distanceAt].
  double depthAtDistance(double distance) =>
      (1 / distance - 1 / farDistance) / (1 / nearDistance - 1 / farDistance);

  /// How far in front of the street line something at [depth] really is,
  /// world units (below 0 behind it): what light and rain use for depth,
  /// not the depth itself, which is linear on the screen.
  double ahead(double depth) => farDistance - distanceAt(depth);

  /// The depth of what lies [inFront] world units in front of the street
  /// line: the inverse of [ahead].
  double depthAhead(double inFront) => depthAtDistance(farDistance - inFront);

  /// How much bigger, and faster across the view, something at [depth] is
  /// than on the street line: below 1 behind it, above 1 in front.
  double scaleAt(double depth) => farDistance / distanceAt(depth);

  /// The depth at which things are [scale] times as big, and as fast across
  /// the view, as on the street line: what a parallax layer drawn at that
  /// scale stands at.
  double depthOfScale(double scale) =>
      (scale - 1) / (farDistance * (1 / nearDistance - 1 / farDistance));

  /// World y where something at [depth] meets the ground: the street line
  /// for anything on or behind it (the line hides the ground behind), lower
  /// the nearer it stands.
  double yAt(double depth) => band.top + depth.clamp(0.0, 1.0) * band.height;

  /// The depth of the ground seen at world [y]: 0 on the street line, 1 the
  /// nearest in view.
  double depthAt(double y) => ((y - band.top) / band.height).clamp(0.0, 1.0);

  /// World x at which something at road position [x] and [depth] is seen
  /// while the view is centred on [focusX]: things nearer the eye slide by
  /// faster, farther ones slower (parallax).
  double projectX(double x, double depth, double focusX) =>
      focusX + (x - focusX) * scaleAt(depth);

  /// The sine of the angle the eye looks down onto the ground at [depth]:
  /// small far off (it looks along the ground), larger near.
  double sinElevation(double depth) {
    final distance = distanceAt(depth);
    return eyeHeight / math.sqrt(eyeHeight * eyeHeight + distance * distance);
  }

  /// The projection for shaders, as one vec4 and a float: band top, band
  /// height, near distance, far distance, eye height. A shader works out
  /// depth, distance and elevation from these exactly as this class does.
  void writeUniforms(Float32List into, int at) {
    into
      ..[at] = band.top
      ..[at + 1] = band.height
      ..[at + 2] = nearDistance
      ..[at + 3] = farDistance
      ..[at + 4] = eyeHeight;
  }

  /// Floats [writeUniforms] writes.
  static const int uniformFloats = 5;

  @override
  bool operator ==(Object other) =>
      other is StreetProjection && other.band == band && other.camera == camera;

  @override
  int get hashCode => Object.hash(band, camera);
}
