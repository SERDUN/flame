/// Water for Flame side-view scenes: surfaces that mirror the world above
/// them, ripples from rain, wet ground.
///
/// Where Flutter GPU is on, a water surface moves by the wave equation run on
/// the GPU (drops dent it, the rings spread, cross and reflect off its
/// edges); elsewhere - the web, tests, an app without the flag - by its
/// rings. To turn it on, an app sets `FLTEnableFlutterGPU` to true in its
/// iOS and macOS Info.plist and, on Android, adds
/// `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU"
/// android:value="true" />` to its manifest's application. The wave shaders
/// are built by this package's build hook into
/// `build/shaderbundles/flame_water.shaderbundle`.
library;

export 'src/rain.dart' show Rain, RainSlice;
export 'src/rain_catcher.dart' show RainCatcher;
export 'src/rain_deflector.dart' show RainBounce, RainDeflector;
export 'src/rain_drops.dart' show RainDrops;
export 'src/reflection_pass.dart' show ReflectionPass, Reflectable;
export 'src/ripple_rings.dart' show RippleRings;
export 'src/water_shader.dart' show WaterShader;
export 'src/water_surface.dart' show WaterQuality, WaterShape, WaterSurface;
export 'src/wettable.dart' show WetSheen, Wettable;
