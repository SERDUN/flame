## 0.1.0

- `Lighting`: the stage's night - darkness cut by every light of the frame on the wall plane and as the pool it lays on the ground, halos in the haze, the moon lifting the dark - with the shadows of whatever stands in a light's way.
- `LightSource`: a component carrying any `Light` (bulb, cone, window, tube) and drawing its glowing part.
- `Glossy`: a wet surface the lights glint off, with damp trails where light falls.
- `LightReflector`: a surface (water, a wet road) that mirrors the frame's lights over the night.
- `LightShader`: the one shader every light is drawn with.
- `LightBuffer`: where flutter_gpu is on, every light added up once a frame into a float image; the night, the light cast and every sheen are one draw each of it.
