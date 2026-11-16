Fix bearing type definition in fluid flow
The bearing is currently being defined wrongly. Instead of taking the diameter to calculate the ratio between it and the bearing length, we are taking the radius.

### Additional contract requirements

- The bearing type is determined by the ratio between the bearing length and the bearing diameter (twice the stator radius): `bearing_type` is `"short_bearing"` when `length / diameter <= 1/8`, `"long_bearing"` when `length / diameter > 4`, and `"medium_size"` otherwise.
