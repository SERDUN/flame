/// The stage a 2.5D side-view Flame scene plays on: its one depth
/// projection, who is on it, what each frame of it holds, and the light that
/// falls on it, the weather over it and what its surfaces are made of - so
/// the systems of a scene (light, water, rain) share these as data made once
/// a frame instead of walking the tree for each other.
library;

export 'src/air.dart';
export 'src/color_temperature.dart';
export 'src/daylight.dart';
export 'src/depth.dart';
export 'src/form.dart';
export 'src/light_field.dart'
    show
        Ambience,
        Falloff,
        Light,
        LightCarrier,
        LightField,
        LightSample,
        LightShape;
export 'src/shadow.dart' show ShadowCaster, ShadowSet, UprightShadow;
export 'src/sky_view.dart';
export 'src/stage.dart' show FrameStep, Ground, OnStage, Stage, StageFrame;
export 'src/street_projection.dart' show DepthCamera, StreetProjection;
export 'src/substance.dart';
export 'src/water_medium.dart';
export 'src/weather.dart';
