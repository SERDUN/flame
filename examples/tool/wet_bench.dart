// Runs the rainy night alone and prints frame timings every 2 s:
// flutter run -d macos --profile -t tool/wet_bench.dart
// --dart-define=BENCH_WITHOUT=lighting,water,rain leaves those out, to see
// what each costs.
import 'package:examples/stories/wet_world/rainy_night_example.dart';
import 'package:flame/game.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/flame_water.dart';
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
  runApp(GameWidget(game: _Bench()));
}

// A bench tool: its knob comes from the build.
// ignore: do_not_use_environment
const _without = String.fromEnvironment('BENCH_WITHOUT');

class _Bench extends RainyNightExample {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final out = _without.split(',');
    world.removeAll([
      for (final c in world.descendants())
        if ((out.contains('lighting') && c is Lighting) ||
            (out.contains('water') && c is WaterSurface) ||
            (out.contains('rain') && c is Rain))
          c,
    ]);
  }
}
