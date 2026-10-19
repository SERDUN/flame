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
}
