import 'dart:math' as math;

import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets [body] fly in [air] for [seconds] at 60 steps a second, calling
/// [each] after every step.
void _fly(
  AirBody body,
  AirVelocity air,
  double seconds, [
  void Function()? each,
]) {
  const dt = 1 / 60;
  for (var i = 0; i < seconds / dt; i++) {
    body.fly(dt, air);
    each?.call();
  }
}

void main() {
  group('AirBody', () {
    test('in still air a leaf falls about as fast as a plate face on', () {
      final leaf = AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 50,
        angle: 0.4,
      );
      _fly(leaf, AirVelocity(), 6);
      // Face on it settles at sqrt(2 m g / (rho A Cd)); it swings round that.
      const kind = AirBodyKind.leaf;
      final faceOn = math.sqrt(
        2 * kind.massKg * AirBody.gravity / (1.2 * kind.areaM2 * kind.faceDrag),
      );
      expect(
        (50 - leaf.height) / 6,
        inInclusiveRange(faceOn * 0.6, faceOn * 1.6),
      );
    });

    test('the eddies of a breeze make it sway and wander as it falls', () {
      final random = math.Random(3);
      final leaf = AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 50,
        angle: 0.4,
      );
      final breeze = AirVelocity()..set(2, 0, 0);
      var turns = 0;
      var last = leaf.vAlong - 2;
      const dt = 1 / 60;
      final paths = <double>[];
      for (var i = 0; i < 6 / dt; i++) {
        leaf
          ..stir(
            dt,
            AirStir.nearGround(
              meanSpeed: 2,
              height: leaf.height,
              roughnessM: 0.1,
            ),
            random,
          )
          ..fly(dt, breeze);
        final rel = leaf.vAlong - 2;
        if (rel.sign != last.sign) {
          turns++;
        }
        last = rel;
        paths.add(leaf.x - 2 * i * dt);
      }
      // It strays round the wind's way, back and forth, a good way.
      expect(turns, greaterThanOrEqualTo(3));
      expect(paths.reduce(math.max) - paths.reduce(math.min), greaterThan(0.3));
      expect(leaf.height.isFinite && leaf.angle.isFinite, isTrue);
    });

    test(
      'near the ground the eddies are as strong as its roughness makes them',
      () {
        final town = AirStir.nearGround(
          meanSpeed: 5,
          height: 2,
          roughnessM: 0.5,
        );
        final lake = AirStir.nearGround(
          meanSpeed: 5,
          height: 2,
          roughnessM: 0.0002,
        );
        // A town street stirs a 5 m/s wind by about 1.4 m/s, open water by 0.5.
        expect(town.sigma, closeTo(2.4 * 0.4 * 5 / math.log(2 / 0.5), 1e-9));
        expect(lake.sigma, lessThan(town.sigma / 2));
        expect(
          AirStir.nearGround(meanSpeed: 0, height: 2, roughnessM: 0.5).sigma,
          0,
        );
      },
    );

    test(
      'just over the ground the wind blows as slow as the surface is rough',
      () {
        final road = AirStir.windShare(height: 0.02, surfaceM: 0.0005);
        final grass = AirStir.windShare(height: 0.02, surfaceM: 0.016);
        expect(
          road,
          closeTo(math.log(0.02 / 0.0005) / math.log(2 / 0.0005), 1e-9),
        );
        expect(grass, lessThan(road / 3));
        expect(AirStir.windShare(height: 0.01, surfaceM: 0.02), 0);
        expect(AirStir.windShare(height: 5, surfaceM: 0.02), 1);
      },
    );

    test('a strip of paper comes down unlike a leaf', () {
      final leaf = AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 20,
        angle: 0.3,
      );
      final paper = AirBody(
        AirBodyKind.paper,
        x: 0,
        ahead: 0,
        height: 20,
        angle: 0.3,
      );
      final still = AirVelocity();
      _fly(leaf, still, 4);
      _fly(paper, still, 4);
      // Lighter for its face, the paper comes down slower.
      expect(paper.height, greaterThan(leaf.height + 0.5));
      expect(paper.height.isFinite && paper.angle.isFinite, isTrue);
    });

    test('a steady wind carries it at its own speed', () {
      final leaf = AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 200,
        angle: 0.2,
      );
      final wind = AirVelocity()..set(6, 0, 0);
      var drift = 0.0;
      _fly(leaf, wind, 8);
      final x0 = leaf.x;
      _fly(leaf, wind, 4);
      drift = (leaf.x - x0) / 4;
      expect(drift, closeTo(6, 0.6));
    });

    test('a wind across the view carries it toward the eye', () {
      final leaf = AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 200,
        yaw: 0.7,
        angle: 0.2,
      );
      final wind = AirVelocity()..set(0, 4, 0);
      _fly(leaf, wind, 10);
      expect(leaf.ahead, greaterThan(25));
      expect(leaf.x.abs(), lessThan(leaf.ahead));
    });

    test('lying, the wind lifts it once it pushes past its hold', () {
      AirBody lying() => AirBody(
        AirBodyKind.leaf,
        x: 0,
        ahead: 0,
        height: 0,
        rest: AirBodyRest.lying,
      );
      final calm = AirVelocity()..set(1, 0, 0);
      final gale = AirVelocity()..set(9, 0, 0);
      expect(lying().liftsIn(calm, Substance.asphalt), isFalse);
      final lifted = lying();
      expect(lifted.liftsIn(gale, Substance.asphalt), isTrue);
      expect(lifted.rest, AirBodyRest.flying);
      // Up and away downwind, not straight back down.
      _fly(lifted, gale, 0.5);
      expect(lifted.x, greaterThan(0.5));
    });

    test('soaked, it sticks where a dry one lifts', () {
      final wind = AirVelocity()..set(5, 0, 0);
      final dry = AirBody(
        AirBodyKind.paper,
        x: 0,
        ahead: 0,
        height: 0,
        rest: AirBodyRest.lying,
      );
      final wet = AirBody(
        AirBodyKind.paper,
        x: 0,
        ahead: 0,
        height: 0,
        rest: AirBodyRest.lying,
      )..waterMm = AirBodyKind.paper.holdsMm;
      expect(dry.liftsIn(wind, Substance.asphalt), isTrue);
      expect(wet.liftsIn(wind, Substance.asphalt), isFalse);
    });

    test('rain soaks it and dry air takes it back', () {
      final paper = AirBody(
        AirBodyKind.paper,
        x: 0,
        ahead: 0,
        height: 0,
        rest: AirBodyRest.lying,
      );
      final rain = WeatherState()
        ..present = true
        ..rainMmPerHour = 6
        ..humidity = 1
        // The world's time runs a minute a second.
        ..pace = 60;
      for (var i = 0; i < 600; i++) {
        paper.soak(rain, 0.1);
      }
      expect(paper.wetness, 1);
      final dry = WeatherState()
        ..present = true
        ..humidity = 0.4
        ..temperature = 20
        ..pace = 60;
      for (var i = 0; i < 600; i++) {
        paper.soak(dry, 0.1);
      }
      expect(paper.wetness, lessThan(1));
    });

    test('afloat, it drifts at a few hundredths of the wind', () {
      final leaf = AirBody(AirBodyKind.leaf, x: 0, ahead: 3, height: 0)
        ..settle(onWater: true);
      leaf.drift(10, AirVelocity()..set(5, 0, 0));
      expect(leaf.x, closeTo(5 * AirBody.floatDrift * 10, 1e-9));
    });

    test('its corners lie flat on the ground and turn with it', () {
      final leaf = AirBody(AirBodyKind.leaf, x: 1, ahead: 2, height: 0)
        ..settle(onWater: false);
      final corners = List<double>.filled(12, 0);
      leaf.cornersInto(corners);
      for (var i = 0; i < 4; i++) {
        expect(corners[i * 3 + 2], 0);
      }
      leaf
        ..angle = math.pi / 2
        ..cornersInto(corners);
      final ups = [for (var i = 0; i < 4; i++) corners[i * 3 + 2]];
      expect(
        ups.reduce(math.max) - ups.reduce(math.min),
        closeTo(AirBodyKind.leaf.chordM, 1e-9),
      );
    });
  });
}
