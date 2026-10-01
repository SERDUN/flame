## 0.1.0

- `StreetProjection`: the one depth projection of a side-view street, a value made once a frame.
- `OnStage`: a component on the stage; every role (`Ground`, `LightCarrier`, `Ambience`, `ShadowCaster`) asks for it.
- `Ground`: what gives the projection its band.
- `Stage`: a world's registry of who is on it and its frame, built once before the rest update.
- `LightField`: every light of a frame as data - point, cone, area, line, directional - and how much reaches a point.
- `ShadowSet`: what stands in the light's way, as capsules at street depths, with a penumbra as wide as the light's source.
