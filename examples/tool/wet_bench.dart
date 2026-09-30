// Runs the rainy night alone and prints frame timings every 2 s:
// flutter run -d macos --profile -t tool/wet_bench.dart
import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final build = <int>[];
  final raster = <int>[];
  var windows = 0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
    if (build.length >= 240) {
      build.sort();
      raster.sort();
      int p(List<int> l, double q) => l[(l.length * q).floor()];
      windows++;
      debugPrint(
        'bench $windows: ui p50 ${p(build, .5)} p90 ${p(build, .9)} us, '
        'raster p50 ${p(raster, .5)} p90 ${p(raster, .9)} us '
        '(${build.length} frames)',
      );
      build.clear();
      raster.clear();
    }
  });
  runApp(GameWidget(game: RainyNightExample()));
}
