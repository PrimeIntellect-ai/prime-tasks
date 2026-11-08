Angle wrapping fails for `PiecewiseNormSpatialModel`
I came across this problem in #5082

# Example
Create `PiecewiseNormSpatialModel`
```python
from gammapy.maps import WcsGeom, MapCoord
import astropy.units as u

geom = WcsGeom.create(skydir=(0, 0), npix=(2, 2), binsz=0.3, frame="galactic")
coords = MapCoord.create(geom.footprint)
coords["lon"] *= u.deg
coords["lat"] *= u.deg

model = PiecewiseNormSpatialModel(coords, frame="galactic")
model.to_dict()
```
```python
Out[104]:
{'spatial': {'type': 'PiecewiseNormSpatialModel',
  'frame': 'galactic',
  'parameters': [{'name': 'norm_0', 'value': 1.0},
   {'name': 'norm_1', 'value': 1.0},
   {'name': 'norm_2', 'value': 1.0},
   {'name': 'norm_3', 'value': 1.0}],
  'lon': {'data': [0.15, 0.15, -0.14999999999997726, -0.14999999999997726],
   'unit': 'deg'},
  'lat': {'data': [-0.15, 0.15, 0.15, -0.15], 'unit': 'deg'}}}
```
Creating a new instance from the dict changes the lon values:
```python
PiecewiseNormSpatialModel.from_dict(model.to_dict()).to_dict()
```
```python
{'spatial': {'type': 'PiecewiseNormSpatialModel',
  'frame': 'galactic',
  'parameters': [{'name': 'norm_0', 'value': 1.0},
   {'name': 'norm_1', 'value': 1.0},
   {'name': 'norm_2', 'value': 1.0},
   {'name': 'norm_3', 'value': 1.0}],
  'lon': {'data': [-359.85,
    -359.85,
    -0.14999999999997726,
    -0.14999999999997726],
   'unit': 'deg'},
  'lat': {'data': [-0.15, 0.15, 0.15, -0.15], 'unit': 'deg'}}}
```

This is because of the wrapping of the Angle in the init of the class
https://github.com/gammapy/gammapy/blob/90459a5bb99d7b22f0230627c05268d94212ffbc/gammapy/modeling/models/spatial.py#L1668-L1673

**But:** Why are the lon values not getting wrapped in the creation of the first model above?
