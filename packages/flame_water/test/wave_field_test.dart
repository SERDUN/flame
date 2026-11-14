import 'dart:typed_data';

import 'package:flame_water/src/wave_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thinning keeps the drops asked for and all their depth', () {
    final drops = <double>[
      for (var i = 0; i < 100; i++) ...[i / 100, 0.5, 2.5, 1],
    ];
    thinDrops(drops, 16);
    expect(drops.length, 16 * 4);
    var depth = 0.0;
    for (var i = 3; i < drops.length; i += 4) {
      depth += drops[i];
    }
    expect(depth, closeTo(100, 1e-9));
    // Spread over the whole field, not only its first drops.
    expect(drops[(15 * 4)], greaterThan(0.9));
  });

  test('thinning leaves a short queue as it is', () {
    final drops = <double>[0.1, 0.2, 2.5, 1, 0.3, 0.4, 2.5, 0.5];
    thinDrops(drops, 16);
    expect(drops, [0.1, 0.2, 2.5, 1, 0.3, 0.4, 2.5, 0.5]);
  });

  test('a batch of drops lands over the steps after it, sixteen a step, '
      'none folded in', () {
    final queue = DropQueue(perStep: 16, hold: 128);
    // A slow frame's rain, landed in one go.
    for (var i = 0; i < 100; i++) {
      queue.add(i / 100, 0.5, 2.5, 1);
    }
    final params = Float32List(16 * 4);
    var landed = 0;
    var depth = 0.0;
    var steps = 0;
    while (queue.length > 0) {
      queue.beforeSteps(1);
      final count = queue.takeInto(params, 0);
      expect(count, lessThanOrEqualTo(16));
      for (var i = 0; i < count; i++) {
        depth += params[i * 4 + 3];
      }
      landed += count;
      steps++;
    }
    expect(landed, 100, reason: 'each drop where it fell');
    expect(depth, closeTo(100, 1e-6));
    expect(steps, 7);
  });

  test('past its hold the queue folds drops in, about as deep in all', () {
    final queue = DropQueue(perStep: 16, hold: 128);
    for (var i = 0; i < 1000; i++) {
      queue.add(i / 1000, 0.5, 2.5, 1);
    }
    expect(queue.length, lessThan(2 * 128));
    queue.beforeSteps(1);
    expect(queue.length, 128);
    final params = Float32List(16 * 4);
    var depth = 0.0;
    while (queue.length > 0) {
      final count = queue.takeInto(params, 0);
      for (var i = 0; i < count; i++) {
        depth += params[i * 4 + 3];
      }
    }
    // Folded twice over, drops of different depths are sampled, not summed.
    expect(depth, closeTo(1000, 100));
  });
}
