import 'dart:math' as math;
import 'dart:ui';

/// The colour of light a body at [kelvin] gives (a black body, Tanner
/// Helland's fit, good from 1000 K to 40000 K): a sodium street lamp about
/// 2000 K, a warm bulb 2700, a white LED 4000, daylight 6500, an overcast
/// sky 7000.
Color colorOfKelvin(double kelvin) {
  final t = kelvin.clamp(1000.0, 40000.0) / 100;
  double red;
  double green;
  double blue;
  if (t <= 66) {
    red = 255;
    green = 99.4708025861 * math.log(t) - 161.1195681661;
  } else {
    red = 329.698727446 * math.pow(t - 60, -0.1332047592);
    green = 288.1221695283 * math.pow(t - 60, -0.0755148492);
  }
  if (t >= 66) {
    blue = 255;
  } else if (t <= 19) {
    blue = 0;
  } else {
    blue = 138.5177312231 * math.log(t - 10) - 305.0447927307;
  }
  return Color.fromARGB(
    255,
    red.clamp(0, 255).round(),
    green.clamp(0, 255).round(),
    blue.clamp(0, 255).round(),
  );
}
