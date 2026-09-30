import 'package:dashbook/dashbook.dart';
import 'package:examples/stories/wet_world/mirror_puddle_example.dart';
import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:examples/stories/wet_world/ripples_example.dart';
import 'package:flame/game.dart';

/// These samples live in the SERDUN fork, not upstream.
String _forkLink(String path) =>
    'https://github.com/SERDUN/flame/blob/serdun/examples/lib/stories/wet_world/$path';

void addWetWorldStories(Dashbook dashbook) {
  dashbook.storiesOf('Wet world')
    ..add(
      'Rainy night',
      (context) => GameWidget(
        game: RainyNightExample(
          darkness: context.numberProperty('darkness', 0.7),
          glow: context.numberProperty('glow', 0.35),
          haze: context.numberProperty('haze', 0.5),
          rain: context.numberProperty('rain', 1),
          wetness: context.numberProperty('ground wetness', 1),
        ),
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
