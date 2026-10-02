import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_stage/src/daylight.dart';
import 'package:flame_stage/src/stage.dart';

/// The weather over a stage: one state the rain, the air, the light and
/// every wet thing follow, in physical terms.
///
/// How hard it rains (mm an hour), the wind, the air's humidity and
/// temperature, how much of the sky clouds cover, and how fast the world's
/// time runs against the game's ([pace]: a run that goes from dusk to night
/// in minutes runs the world faster). One on a stage; the stage reads it
/// once a frame into [StageFrame.weather].
mixin Weather on OnStage {
  /// Rain, mm an hour: 1 a drizzle, 6 a steady rain, 15 a downpour.
  double get rainMmPerHour;

  /// The wind, m/s (y down).
  Vector2 get wind;

  /// The air's relative humidity, `0..1`.
  double get humidity => 0.8;

  /// The air's temperature, degrees Celsius.
  double get temperature => 12;

  /// How much of the sky clouds cover, `0..1`.
  double get cloudCover => 1;

  /// How thick the clouds are to light, their optical depth: some 27 a
  /// common overcast, 70 one it rains steadily from, over 150 a
  /// thunderhead (`Daylight.cloudTransmittance`). By default, the cloud the
  /// rain falls from ([cloudOpticalDepthOfRain]).
  double get cloudOpticalDepth => cloudOpticalDepthOfRain(rainMmPerHour);

  /// World seconds a second of the game: how fast water comes and goes, and
  /// the day turns.
  double get pace => 1;
}

/// The optical depth of the clouds a rain of [mmPerHour] falls from: the
/// thicker the cloud, the more water it holds and the harder it rains -
/// some 40 for a drizzle (1 mm/h), 70 a steady rain (6), 110 a downpour
/// (15), 185 a thunderhead's (40) (rough, after the liquid water paths
/// such clouds carry).
double cloudOpticalDepthOfRain(double mmPerHour) =>
    Daylight.overcastOpticalDepth +
    12 * math.pow(math.max(mmPerHour, 0), 0.7).toDouble();

/// The weather of one frame, as the stage read it: what everything wet,
/// the air and the sky ask of it.
class WeatherState {
  /// Whether a [Weather] gave it; without one the air is still and dry and
  /// no rain falls.
  bool present = false;

  /// Rain, mm an hour.
  double rainMmPerHour = 0;

  /// The wind, m/s (y down).
  final Vector2 wind = Vector2.zero();

  /// Relative humidity, `0..1`.
  double humidity = 0.6;

  /// Degrees Celsius.
  double temperature = 15;

  /// `0..1`.
  double cloudCover = 0;

  /// The clouds' optical depth.
  double cloudOpticalDepth = 0;

  /// World seconds a game second.
  double pace = 1;

  /// The rain a scene was tuned for, mm an hour.
  static const double tunedRainMmPerHour = 6;

  /// How hard it rains against the rain the scene was tuned for: 1 steady,
  /// 2 a downpour, 0 dry.
  double get rainIntensity => rainMmPerHour / tunedRainMmPerHour;

  /// How fast still water evaporates, mm an hour (Dalton's law): as much as
  /// the air is short of saturated, faster in a wind. In rain the air is
  /// saturated and nothing dries.
  double get evaporationMmPerHour {
    final saturated =
        0.6108 * math.exp(17.27 * temperature / (temperature + 237.3));
    final short = saturated * (1 - humidity.clamp(0.0, 1.0));
    return (0.12 + 0.06 * wind.length) * short;
  }

  /// How thick the air is with water, `0..1`: what haloes every light.
  double get haze {
    final rain = (rainIntensity / 2).clamp(0.0, 1.0);
    final damp = ((humidity - 0.75) / 0.25).clamp(0.0, 1.0);
    return (0.08 + 0.45 * rain + 0.3 * damp).clamp(0.0, 1.0);
  }

  /// How far one sees, m (Koschmieder): clear air some 20 km, rain and mist
  /// scatter the light and bring it in.
  double get visibilityM {
    final rain = 3.5e-4 * math.pow(math.max(rainMmPerHour, 0), 0.63);
    final mist = 2e-3 * math.pow(((humidity - 0.9) / 0.1).clamp(0.0, 1.0), 2);
    return 1 / (1 / 20000 + rain + mist);
  }

  /// Takes [weather]'s state; with none, a still dry day.
  void read(Weather? weather) {
    present = weather != null;
    if (weather == null) {
      rainMmPerHour = 0;
      wind.setZero();
      humidity = 0.6;
      temperature = 15;
      cloudCover = 0;
      cloudOpticalDepth = 0;
      pace = 1;
      return;
    }
    rainMmPerHour = math.max(weather.rainMmPerHour, 0);
    cloudOpticalDepth = math.max(weather.cloudOpticalDepth, 0);
    wind.setFrom(weather.wind);
    humidity = weather.humidity.clamp(0.0, 1.0);
    temperature = weather.temperature;
    cloudCover = weather.cloudCover.clamp(0.0, 1.0);
    pace = math.max(weather.pace, 0);
  }
}
