import 'package:flame_water/flame_water.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a ring grows and fades over its life, then is gone', () {
    final rings = RippleRings(lifeSec: 1, maxRadius: 10)..add(0, 0);
    final (r0, a0) = rings.ring(0)!;
    rings.update(0.5);
    final (r1, a1) = rings.ring(0)!;
    expect(r1, greaterThan(r0));
    expect(a1, lessThan(a0));
    rings.update(0.6);
    expect(rings.ring(0), isNull);
    expect(rings.count, 0);
  });

  test('a full pool gives the oldest ring away', () {
    final rings = RippleRings(capacity: 3);
    for (var i = 0; i < 5; i++) {
      rings.add(i.toDouble(), 0);
    }
    expect(rings.count, 3);
  });

  test('a weak drop makes a smaller, fainter ring', () {
    final rings = RippleRings()
      ..add(0, 0)
      ..add(0, 0, strength: 0.2)
      ..update(0.2);
    final (strongR, strongA) = rings.ring(0)!;
    final (weakR, weakA) = rings.ring(1)!;
    expect(weakR, lessThan(strongR));
    expect(weakA, lessThan(strongA));
  });
}
