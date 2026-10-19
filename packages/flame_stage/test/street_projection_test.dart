import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The band 100 tall from y 400: the street line 600 from the eye, the
  // nearest ground 200.
  final road = StreetProjection(const Rect.fromLTWH(0, 400, 800, 100));

  test(
    'one projection: where things stand, how big and how fast they pass',
    () {
      expect(road.farDistance, 600);
      expect(road.scaleAt(0), closeTo(1, 1e-9));
      expect(road.scaleAt(1), closeTo(3, 1e-9));
      expect(road.scaleAt(-0.25), lessThan(1), reason: 'behind the line');
      expect(road.yAt(0), 400);
      expect(road.yAt(-1), 400, reason: 'the line hides the ground behind');
      expect(road.yAt(0.5), 450);
      expect(road.depthAt(road.yAt(0.3)), closeTo(0.3, 1e-9));
      // Equal steps of distance crowd towards the street line.
      final far = road.distanceAt(0) - road.distanceAt(0.25);
      final near = road.distanceAt(0.75) - road.distanceAt(1);
      expect(far, greaterThan(near * 3));
      expect(
        road.projectX(500, 1, 400),
        700,
        reason: 'near things pass faster',
      );
      expect(road.projectX(500, 0, 400), 500);
      expect(road.sinElevation(1), greaterThan(road.sinElevation(0)));
      expect(road.scaleAt(road.depthOfScale(0.35)), closeTo(0.35, 1e-9));
      expect(road.depthOfScale(1), 0);
    },
  );

  test('how far in front of the line a depth is, and back', () {
    expect(road.ahead(0), closeTo(0, 1e-9));
    expect(road.ahead(1), closeTo(road.span, 1e-9));
    // Not linear in depth: rows crowd towards the line, so half way down
    // the band is already more than half the span in front of it (300 of
    // 400 here), and depth times span would put it 100 short.
    expect(road.ahead(0.5), closeTo(300, 1e-9));
    for (final depth in [-0.4, 0.0, 0.3, 0.8, 1.0]) {
      expect(road.depthAhead(road.ahead(depth)), closeTo(depth, 1e-9));
      expect(
        road.depthAtDistance(road.distanceAt(depth)),
        closeTo(depth, 1e-9),
      );
    }
  });

  test('the optics are the camera, not getters to override', () {
    final wide = StreetProjection(
      const Rect.fromLTWH(0, 400, 800, 100),
      camera: const DepthCamera(spanPerBand: 8),
    );
    expect(wide.span, 800);
    expect(wide.scaleAt(1), greaterThan(road.scaleAt(1)));
    expect(wide == road, isFalse);
    expect(
      StreetProjection(const Rect.fromLTWH(0, 400, 800, 100)) == road,
      isTrue,
    );
  });

  test('a shader gets the projection as five floats', () {
    final into = Float32List(StreetProjection.uniformFloats);
    road.writeUniforms(into, 0);
    expect(into, [400, 100, 200, 600, 65]);
  });
}
