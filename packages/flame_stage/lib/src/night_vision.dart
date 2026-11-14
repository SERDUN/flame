import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// How the eye sees colour in the light it has adapted to (the Purkinje
/// shift): in daylight the cones see every colour; as the eye adapts to
/// less and less light the rods take over, which see no colour and see blue
/// and green best, so the world fades toward grey and turns bluer. Under a
/// lamp the eye is still on its cones there and the colour comes back.
///
/// The amount of it, [amountAt], goes from 0 at [noneAbove] (the cones
/// alone, photopic) to 1 at [fullBelow] (dark-adapted, scotopic), as a
/// smooth step over the logarithm of the level between them (the mesopic
/// range, where both work). What it does to a colour at an amount
/// ([apply], [matrix]) is a linear map: the colour pulled toward its own
/// luminance, leaving [keptSaturation] of its saturation at the full
/// amount, and tinted by [tint] - one colour matrix, so it costs nothing
/// on the GPU beyond the paint a layer is laid down with.
class NightVision {
  const NightVision({
    required this.fullBelow,
    required this.noneAbove,
    this.keptSaturation = 0.3,
    this.tint = const (0.82, 0.97, 1.18),
  });

  /// The adapted level, in lights' units (`LightField.exposure` is one
  /// over it), at and under which the shift is whole: the dark-adapted eye.
  final double fullBelow;

  /// The adapted level at and over which there is none: the cones alone.
  final double noneAbove;

  /// The share of a colour's saturation left at the whole shift, `0..1`:
  /// the rods alone would leave none; some is kept so a night stays a
  /// scene and not a grey photograph.
  final double keptSaturation;

  /// What each channel is multiplied by at the whole shift: toward the
  /// blue-green the rods see best (their peak is near 507 nm). About as
  /// bright as no tint at all (luminance 0.95), so the shift fades and
  /// cools a colour and does not light it.
  final (double, double, double) tint;

  /// Rec. 709 luminance weights.
  static const double _wr = 0.2126;
  static const double _wg = 0.7152;
  static const double _wb = 0.0722;

  /// The shift, `0..1`, for an eye adapted to [level].
  double amountAt(double level) {
    if (!(level > 0)) {
      return 1;
    }
    if (noneAbove <= fullBelow) {
      return level <= fullBelow ? 1 : 0;
    }
    final t =
        ((math.log(noneAbove) - math.log(level)) /
                (math.log(noneAbove) - math.log(fullBelow)))
            .clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// [color] as the eye sees it at a shift of [amount]; [color] itself at 0.
  Color apply(Color color, double amount) {
    final s = amount.clamp(0.0, 1.0);
    if (s == 0) {
      return color;
    }
    final fade = s * (1 - keptSaturation.clamp(0.0, 1.0));
    final y = _wr * color.r + _wg * color.g + _wb * color.b;
    double channel(double c, double t) =>
        ((c + (y - c) * fade) * (1 + (t - 1) * s)).clamp(0.0, 1.0);
    return Color.from(
      alpha: color.a,
      red: channel(color.r, tint.$1),
      green: channel(color.g, tint.$2),
      blue: channel(color.b, tint.$3),
    );
  }

  /// [apply] as a 4 x 5 colour matrix ([ColorFilter.matrix]), row by row;
  /// alpha is kept, and nothing is added, so what is clear stays clear.
  Float64List matrix(double amount) {
    final s = amount.clamp(0.0, 1.0);
    final fade = s * (1 - keptSaturation.clamp(0.0, 1.0));
    const w = [_wr, _wg, _wb];
    final t = [tint.$1, tint.$2, tint.$3];
    final m = Float64List(20);
    for (var row = 0; row < 3; row++) {
      final k = 1 + (t[row] - 1) * s;
      for (var col = 0; col < 3; col++) {
        final own = row == col ? 1 - fade : 0.0;
        m[row * 5 + col] = k * (own + fade * w[col]);
      }
    }
    m[18] = 1;
    return m;
  }
}
