## 0.1.0

- `WaterSurface` is a `LightMirror` (flame_lighting): the lights above it show in it, drawn out by `lightStretch`.
- `WaterQuality.rippled`: the mirror bent around the rings by the water shader (`WaterShader.load`).

- `WaterSurface`: a stretch of water that mirrors the `Reflectable` part of the world about its water line, clipped to its shape, faded with depth and tinted, without rendering off screen.
- `ReflectionPass`: tells a component it is being drawn as a reflection.
- `RippleRings`: rings spreading from where drops hit, flattened for a side view.
