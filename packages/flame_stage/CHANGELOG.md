## 0.1.0

- `StreetProjection`: the one depth projection of a side-view street, a value made once a frame.
- `Ground`: what gives the projection its band.
- `Stage`: a world's registry of who is on it and its frame, built once before the rest update.
- `LightField`: every light of a frame as data - point, cone, area, line, directional - and how much reaches a point.
