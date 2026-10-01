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

  /// Rain rate at the tuned rain (intensity 1), mm/h: a moderate rain.
  static const double tunedRateMmH = 6;

  /// How long a frame "exposes" a drop, s: a streak is the path the drop covers
  /// meanwhile, as in a photograph at 1/30 s.
  static const double exposureSec = 1 / 20;

  static const double _g = 9.81;

  /// Rain rate for a game intensity (1 = the tuned rain, 2 a downpour, 0.3 a
  /// drizzle), mm/h: heavier rain grows faster than the intensity, as a
  /// downpour is several times a rain.
  static double rateMmH(double intensity) =>
      tunedRateMmH * math.pow(math.max(intensity, 0.05), 1.8);

  /// A drop diameter, mm, for `u` in `0..1` drawn at [intensity]: many small
  /// drops and a few large ones, the large ones more common the harder it
  /// rains.
  static double diameterMm(double u, double intensity) {
    final lambda = 4.1 * math.pow(rateMmH(intensity), -0.21);
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
}
