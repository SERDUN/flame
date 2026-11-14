import 'package:flame_stage/flame_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('things of different kinds sound different under a drop', () {
    // Stone is stone (asphalt and concrete may sound alike); these may not.
    const kinds = [
      Substance.asphalt,
      Substance.brick,
      Substance.glass,
      Substance.metal,
      Substance.canvas,
      Substance.cloth,
      Substance.foliage,
      Substance.soil,
      Substance.wood,
      Substance.water,
    ];
    final sounds = {
      for (final kind in kinds) (kind.soundHz, kind.ringSec, kind.hitSec),
    };
    expect(sounds, hasLength(kinds.length));
  });

  test('a soft thing thuds low, stone clicks high, metal rings longest', () {
    expect(Substance.cloth.soundHz, lessThan(Substance.asphalt.soundHz));
    expect(Substance.soil.soundHz, lessThan(Substance.concrete.soundHz));
    for (final other in [
      Substance.glass,
      Substance.water,
      Substance.wood,
      Substance.canvas,
    ]) {
      expect(Substance.metal.ringSec, greaterThan(other.ringSec));
    }
    expect(
      Substance.canvas.ringSec,
      0,
      reason: 'woven fabric rings at no note',
    );
  });

  test('a crown of leaves lets some through, solid things nothing', () {
    expect(Substance.foliage.cover, lessThan(1));
    expect(Substance.wood.cover, 1);
    expect(Substance.named('foliage'), same(Substance.foliage));
    expect(Substance.named('plastic'), isNull);
    expect(
      Substance.canvas.copyWith(soundHz: 2000).cover,
      Substance.canvas.cover,
    );
  });
}
