incorrect horizon test in tracker.singleaxis
**Describe the bug**
[HIDDEN] sets the tracker rotation angle to `np.nan` when the sun is behind the array plane[HIDDEN]

**To Reproduce**
```
import pvlib
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

loc = pvlib.location.Location(latitude=30, longitude=110)
sat = pvlib.tracking.SingleAxisTracker(axis_tilt=90, axis_azimuth=180, backtrack=False, max_angle=180)
sat.localize(location=loc)

solar_azimuth = pd.Series(data=np.arange(0.0, 359.0))
solar_zenith = 45.0 * solar_azimuth / solar_azimuth

df = sat.singleaxis(apparent_zenith=solar_zenith, apparent_azimuth=solar_azimuth)

p1 = plt.plot(df)
plt.legend(df.columns)
```
The plot shows that the tracker rotation `tracker_theta` is limited to between -90 and 90.

**Expected behavior**
In the above example, the sun rotates in azimuth at 45 zenith. The vertical tracker without rotation limit should follow the sun around the complete circle.

**Screenshots**
![test_sat](https://user-images.githubusercontent.com/5393711/45325941-88428d80-b50f-11e8-918a-2cfc3e8aa460.png)

**Versions:**
 - ``pvlib.__version__``: 0.5.2

**Additional context**

[HIDDEN]

### Additional contract requirements

- Add a public function `singleaxis(apparent_zenith, apparent_azimuth, axis_tilt=0, axis_azimuth=0, max_angle=90, backtrack=True, gcr=2.0/7.0)` in the module `pvlib.tracking`.
- `apparent_zenith` and `apparent_azimuth` may each be a scalar, a 1-D `numpy.ndarray`, or a `pandas.Series`.
- When the inputs are scalars or 1-D `numpy` arrays, the function returns a `dict` whose keys are `tracker_theta`, `aoi`, `surface_azimuth`, and `surface_tilt`.
- When the inputs are `pandas.Series`, the function returns a `pandas.DataFrame` with the same index as the input Series and the columns in the order `['tracker_theta', 'aoi', 'surface_azimuth', 'surface_tilt']`.
- For any element whose apparent zenith angle is greater than 90 degrees, all returned fields for that element are `numpy.nan`.
- For any element where either input angle is `numpy.nan`, all returned fields for that element are `numpy.nan`.
- If either input array has more than one dimension, the function raises `ValueError`.
- With a vertical tracker axis and no effective mechanical rotation limit, when the sun remains at 45 degrees zenith while its azimuth spans the full circle, `tracker_theta` must follow the sun through the full circle rather than being restricted to rotations between -90 and 90 degrees.
