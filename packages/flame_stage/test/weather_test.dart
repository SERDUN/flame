import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storm extends Component with OnStage, Weather {
  @override
  double rainMmPerHour = 12;

  @override
  final Vector2 wind = Vector2(4, 0);

  @override
  double get humidity => 1;

  @override
  double get pace => 60;
}

WeatherState _state({
  double rain = 0,
  double humidity = 0.6,
  double wind = 0,
  double temperature = 15,
}) => WeatherState()
  ..present = true
  ..rainMmPerHour = rain
  ..humidity = humidity
  ..temperature = temperature
  ..wind.setValues(wind, 0);

void main() {
  test('nothing dries in saturated air; warm wind dries fastest', () {
    expect(_state(humidity: 1).evaporationMmPerHour, 0);
    final still = _state().evaporationMmPerHour;
    expect(still, greaterThan(0));
    expect(_state(wind: 5).evaporationMmPerHour, greaterThan(still));
    expect(_state(temperature: 30).evaporationMmPerHour, greaterThan(still));
  });

  test('rain brings the view in and thickens the air', () {
    final dry = _state();
    final storm = _state(rain: 15, humidity: 1);
    expect(storm.visibilityM, lessThan(dry.visibilityM / 4));
    const lamp = (x: 0.0, ahead: 0.0, height: 3.0);
    expect(storm.hazeAt(lamp), greaterThan(dry.hazeAt(lamp)));
    expect(storm.rainIntensity, 2.5);
  });

  testWithFlameGame('the stage reads the weather into the frame', (
    game,
  ) async {
    final storm = _Storm();
    game.world.add(storm);
    await game.ready();
    game.update(1 / 60);
    final weather = storm.stage!.frame.weather;
    expect(weather.present, isTrue);
    expect(weather.rainMmPerHour, 12);
    expect(weather.wind.x, 4);
    expect(weather.pace, 60);
  });

  test('the colour of a lamp follows its temperature', () {
    final sodium = colorOfKelvin(2000);
    final daylight = colorOfKelvin(6500);
    expect(sodium.r, greaterThan(sodium.b * 3));
    expect((daylight.r - daylight.b).abs(), lessThan(0.06));
    expect(colorOfKelvin(10000).b, greaterThan(colorOfKelvin(10000).r));
  });

  test('the eye adapts to brighter light quickly, to dimmer slowly', () {
    final field = LightField();
    void frame(double sky, double dt) {
      field.beginUnder(
        sky: const Color(0xFFFFFFFF),
        skyLight: sky,
        adaptsIn: 1,
      );
      field.finish(dt);
    }

    frame(1, 0);
    expect(field.exposure, 1, reason: 'the first frame sees as adapted');
    frame(10, 1);
    // A second into ten times the light: most of the way, in steps of
    // brightness.
    expect(field.exposure, lessThan(0.3));
    expect(field.exposure, greaterThan(0.1));
    for (var i = 0; i < 60; i++) {
      frame(10, 1);
    }
    expect(field.exposure, closeTo(0.1, 1e-3));
    frame(1, 1);
    expect(field.exposure, lessThan(0.2), reason: 'slow back to the dark');
  });
}
