import 'dart:math' as math;

/// How real raindrops fall, for the rain as drawn. Pure functions: sizes from
/// the rain rate, the speed each size falls at, how quickly it takes up the
/// wind, and the streak a camera would catch of it.
///
/// Sources: drop sizes follow Marshall and Palmer (1948), `N(D) ~ exp(-lambda
/// D)` with `lambda = 4.1 R^-0.21` per mm for a rain rate `R` in mm/h; terminal
/// speeds follow Atlas et al. (1973), `v = 9.65 - 10.3 exp(-0.6 D)` m/s for `D`
/// in mm.
abstract final class RainDrops {
  /// Smallest drop drawn, mm: the drizzle-sized ones below it do not show as
  /// streaks.
  static const double minMm = 0.5;

  /// Largest drop, mm: bigger ones break up as they fall.
  static const double maxMm = 5;

  /// How long a frame "exposes" a drop, s: a streak is the path the drop covers
  /// meanwhile, as in a photograph at 1/30 s.
  static const double exposureSec = 1 / 20;

  /// How long a drop's contrast is integrated over, s: the shutter the streak's
  /// **transparency** is measured at, which is not the shutter its length is
  /// measured at ([exposureSec]).
  ///
  /// Garg & Nayar (2006) give the share of the light a raindrop hides from a
  /// point of its streak as `a = 2 r0 / (v T)` - the drop's diameter over its
  /// speed and the shutter, in metres, metres a second and seconds. This is
  /// that `T`.
  ///
  /// The value is **calibrated, not derived**: 1/1375 s is the shutter that
  /// reproduces the look the rain had when the transparency was a hand-set
  /// constant (0.6 in the game times 0.7 here, over a 2 mm drop). It gives
  /// the number a name and units; it does not explain it. Garg & Nayar's
  /// measured 1/sqrt(T) law of rain's visibility (ICCV 2005) is why the two
  /// shutters differ at all: a 1/20 s shutter would hide the rain altogether
  /// (the fill of a 0.7 mm drop falls to 0.005, 69 times less).
  static const double alphaExposureSec = 1 / 1375;

  static const double _g = 9.81;

  /// A drop diameter, mm, for `u` in `0..1` in a rain of [rainMmPerHour] mm an
  /// hour: many small drops and a few large ones, the large ones more common
  /// the harder it rains.
  ///
  /// The sizes follow the rain's **rate** (Marshall and Palmer 1948: the
  /// number of drops of a diameter `D` in a rain of a rate `R` goes as
  /// `exp(-lambda D)`, with `lambda = 4.1 R^-0.21` per mm), so a rain that
  /// falls harder - a storm cell over the walker, say - has the bigger drops
  /// its rate gives it. The rate is the one number the whole rain is read at:
  /// the air, the cloud and the drops' count follow it too.
  static double diameterMm(double u, double rainMmPerHour) {
    final lambda = 4.1 * math.pow(math.max(rainMmPerHour, 0.05), -0.21);
    // The exponential above minMm, cut at maxMm.
    final d =
        minMm -
        math.log(1 - u * (1 - math.exp(-lambda * (maxMm - minMm)))) / lambda;
    return d.clamp(minMm, maxMm);
  }

  /// Speed a drop of [diameterMm] falls at in still air, m/s.
  static double terminalSpeed(double diameterMm) =>
      math.max(0.5, 9.65 - 10.3 * math.exp(-0.6 * diameterMm));

  /// Seconds a drop falling at [terminal] takes to follow a change of the air
  /// around it (its drag response time `v / g`): a small drop is carried by a
  /// gust almost at once, a large one holds its line for most of a second.
  static double responseSec(double terminal) => terminal / _g;

  /// Share of the gap to the air's velocity a drop closes over [dt] with its
  /// [response] time.
  static double follow(double dt, double response) =>
      1 - math.exp(-dt / math.max(response, 1e-3));

  /// Length of the streak of a drop moving at [speed] m/s, m.
  static double streakLength(double speed) => speed * exposureSec;

  /// The share of the light behind a streak's point that the drop itself
  /// hides: Garg & Nayar's `a = 2 r0 / (v T)`, with the drop's diameter
  /// [diameterMm] in mm, its speed [speed] in m/s and the shutter
  /// [exposureSec] in s - [alphaExposureSec] unless given.
  ///
  /// A small slow drop and a heavy fast one come out alike; a fast small one
  /// is a faint line. Out of focus the streak is blurred over a wider strip
  /// and the light of the drop spreads with it, which is the focus share the
  /// caller applies on top.
  static double streakFill(
    double diameterMm,
    double speed, {
    double exposureSec = alphaExposureSec,
  }) => diameterMm / 1000 / speed / exposureSec;
}
