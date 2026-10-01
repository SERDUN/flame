import 'package:examples/commons/example_use_case.dart';
import 'package:examples/stories/wet_world/mirror_puddle_example.dart';
import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:examples/stories/wet_world/ripples_example.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

/// These samples live in the SERDUN fork, not upstream.
String _forkLink(String path) =>
    'https://github.com/SERDUN/flame/blob/serdun/examples/lib/stories/wet_world/$path';

double _number(BuildContext context, String label, double initial) =>
    context.knobs.double.input(label: label, initialValue: initial);

WidgetbookComponent wetWorldStories() {
  return WidgetbookComponent(
    name: 'Wet world',
    useCases: [
      ExampleUseCase(
        name: 'Rainy night',
        builder: (context) => _RainyNight(
          darkness: _number(context, 'darkness', 0.7),
          glow: _number(context, 'glow', 0.35),
          haze: _number(context, 'haze', 0.5),
          rain: _number(context, 'rain', 1),
          drying: _number(context, 'drying speed', 1),
          wetness: _number(context, 'ground wetness', 1),
        ),
        codeLink: _forkLink('rainy_night_example.dart'),
        info: RainyNightExample.description,
      ),
      ExampleUseCase(
        name: 'Mirror puddle',
        builder: (context) => GameWidget(
          game: MirrorPuddleExample(
            reflectivity: _number(context, 'reflectivity', 0.75),
            squash: _number(context, 'squash', 1),
            fade: _number(context, 'fade', 0.7),
            wetRoadOn: context.knobs.boolean(
              label: 'wet road',
              initialValue: true,
            ),
          ),
        ),
        codeLink: _forkLink('mirror_puddle_example.dart'),
        info: MirrorPuddleExample.description,
      ),
      ExampleUseCase(
        name: 'Ripples',
        builder: (context) => GameWidget(
          game: RipplesExample(rain: _number(context, 'rain', 1)),
        ),
        codeLink: _forkLink('ripples_example.dart'),
        info: RipplesExample.description,
      ),
    ],
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
