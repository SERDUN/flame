import 'package:dashbook/dashbook.dart';
import 'package:examples/stories/wet_world/mirror_puddle_example.dart';
import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:examples/stories/wet_world/ripples_example.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

/// These samples live in the SERDUN fork, not upstream.
String _forkLink(String path) =>
    'https://github.com/SERDUN/flame/blob/serdun/examples/lib/stories/wet_world/$path';

void addWetWorldStories(Dashbook dashbook) {
  dashbook.storiesOf('Wet world')
    ..add(
      'Rainy night',
      (context) => _RainyNight(
        darkness: context.numberProperty('darkness', 0.7),
        glow: context.numberProperty('glow', 0.35),
        haze: context.numberProperty('haze', 0.5),
        rain: context.numberProperty('rain', 1),
        drying: context.numberProperty('drying speed', 1),
        wetness: context.numberProperty('ground wetness', 1),
      ),
      codeLink: _forkLink('rainy_night_example.dart'),
      info: RainyNightExample.description,
    )
    ..add(
      'Mirror puddle',
      (context) => GameWidget(
        game: MirrorPuddleExample(
          reflectivity: context.numberProperty('reflectivity', 0.75),
          squash: context.numberProperty('squash', 0.6),
          fade: context.numberProperty('fade', 0.7),
          wetRoadOn: context.boolProperty('wet road', true),
        ),
      ),
      codeLink: _forkLink('mirror_puddle_example.dart'),
      info: MirrorPuddleExample.description,
    )
    ..add(
      'Ripples',
      (context) => GameWidget(
        game: RipplesExample(
          rain: context.numberProperty('rain', 1),
        ),
      ),
      codeLink: _forkLink('ripples_example.dart'),
      info: RipplesExample.description,
    );
}

/// The rainy night kept running while its properties change: the weather
/// changes on the street as it is, so it dries or soaks in time instead of
/// starting over. Setting the ground wetness wets it that much at once.
class _RainyNight extends StatefulWidget {
  const _RainyNight({
    required this.darkness,
    required this.glow,
    required this.haze,
    required this.rain,
    required this.drying,
    required this.wetness,
  });

  final double darkness;
  final double glow;
  final double haze;
  final double rain;
  final double drying;
  final double wetness;

  @override
  State<_RainyNight> createState() => _RainyNightState();
}

class _RainyNightState extends State<_RainyNight> {
  late final RainyNightExample _game = RainyNightExample(
    darkness: widget.darkness,
    glow: widget.glow,
    haze: widget.haze,
    rain: widget.rain,
    drying: widget.drying,
    wetness: widget.wetness,
  );

  @override
  void didUpdateWidget(_RainyNight old) {
    super.didUpdateWidget(old);
    _game.setWeather(
      darkness: widget.darkness,
      glow: widget.glow,
      haze: widget.haze,
      rain: widget.rain,
      drying: widget.drying,
    );
    if (widget.wetness != old.wetness) {
      _game.setWetness(widget.wetness);
    }
  }

  @override
  Widget build(BuildContext context) => GameWidget(game: _game);
}
