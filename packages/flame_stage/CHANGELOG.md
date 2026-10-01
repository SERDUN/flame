## 0.1.0

- `StreetProjection`: the one depth projection of a side-view street, a value made once a frame.
- `OnStage`: a component on the stage; every role (`Ground`, `LightCarrier`, `Ambience`, `ShadowCaster`) asks for it.
- `Ground`: what gives the projection its band.
- `Stage`: a world's registry of who is on it and its frame, built once before the rest update.
- `LightField`: every light of a frame as data - point, cone, area, line, directional - and how much reaches a point. A cone can throw some of its light all round near its source (`Light.spill`).
- `ShadowSet`: what stands in the light's way, as capsules at street depths, with a penumbra as wide as the light's source.
- `FrameStep`: what a frame's drawing needs made once, before anything in the world draws.
- `Substance`: what a surface is made of - pores, the water it holds, roughness, how a drop bounces and splashes, how loud rain is on it, friction.
- `Weather`: rain in mm an hour, wind, humidity, temperature, clouds and the world's pace, read into `StageFrame.weather` with evaporation, haze and visibility.
- `colorOfKelvin`: a light's colour from its temperature.
- `Ambience.adaptsIn`: the eye adapts over time.
