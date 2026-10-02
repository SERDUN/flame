/// Light and dark for Flame side-view scenes: a night every light of the
/// stage cuts, with the shadows of what stands in its way, sheen on wet
/// walls, a hook for surfaces that mirror the lights, and lights that draw
/// their own glowing parts. The lights themselves, their shapes and the
/// street they fall on are the stage's (`flame_stage`).
library;

export 'src/glossy.dart' show Glossy;
export 'src/light_buffer.dart' show LightBuffer;
export 'src/light_reflector.dart' show LightReflector;
export 'src/light_shader.dart' show LightPlane, LightShader;
export 'src/light_source.dart' show LightSource;
export 'src/lighting.dart' show Lighting, LitLayer;
