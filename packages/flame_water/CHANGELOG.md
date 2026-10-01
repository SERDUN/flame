## 0.1.0

- `WaterSurface.depth` (0 a film on asphalt, 1 a puddle) sets the rings: radius, life, how much they bend the reflection and how plain they show (`RippleRings.forDepth`).

- `WaterSurface` is a `LightReflector` (flame_lighting): every light of the stage's frame shows in it, worked out by the water shader where the mirror puts it, bent by the drops and smeared by a rough surface.
- `Rain` reads the stage's frame: the view, the street's projection, the light on each drop.
- `WaterQuality.rippled`: the mirror bent around the rings by the water shader (`WaterShader.load`).

- `WaterSurface`: a stretch of water that mirrors the `Reflectable` part of the world about its water line, clipped to its shape, faded with depth and tinted, without rendering off screen.
- `ReflectionPass`: tells a component it is being drawn as a reflection.
- `RippleRings`: rings spreading from where drops hit, flattened for a side view.
