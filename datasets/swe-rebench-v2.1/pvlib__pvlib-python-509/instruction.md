klucher results different between pandas and numpy
**Describe the bug**
call `pvlib.irradiance.klucher` with `dhi`, `ghi`, `solar_zenith`, `solar_azimuth` as `pd.Series` and you get different answers than if you user `np.array`

**To Reproduce**
Steps to reproduce the behavior:
```python
import pandas as pd
import numpy as np
import pvlib

surface_tilt = 32.0
surface_azimuth = 180.0
```
#### NumPy Array
```python
nda_apparent_zenith = np.array([
    124.039086298488, 82.8545704390216,10.5641356171064, 72.4168712240143
])  # solar zenith
nda_azimuth = np.array([
    352.695506991832, 66.7141033780672, 144.76567753998, 287.041041278537
])  # solar azimuth
nda_ghi = np.array([0, 79.8826605157945, 1042.48125969315, 257.25820554723])
nda_dhi = np.array([0, 40.4911557248134, 118.458383320548, 62.0343739267192])
# calculate klucher transposition
sky_np = pvlib.irradiance.klucher(
    surface_tilt=surface_tilt,
    surface_azimuth=surface_azimuth,
    dhi=nda_dhi,
    ghi=nda_ghi,
    solar_zenith=nda_apparent_zenith,
    solar_azimuth=nda_azimuth
)
# array([  0.        ,  37.41480162, 109.45839488,  57.32125332])
```
#### Pandas Series
```python
times = pd.date_range(start='2014-06-24', freq='6H', periods=4, tz='US/Arizona')
apparent_zenith = pd.Series(nda_apparent_zenith, index=times)
azimuth = pd.Series(nda_azimuth, index=times)
ghi = pd.Series(nda_ghi, index=times)
dhi = pd.Series(nda_dhi, index=times)
# calculate klucher transposition
sky_pd = pvlib.irradiance.klucher(
    surface_tilt=surface_tilt,
    surface_azimuth=surface_azimuth,
    dhi=dhi,
    ghi=ghi,
    solar_zenith=apparent_zenith,
    solar_azimuth=azimuth
)
# 2014-06-24 00:00:00-07:00      0.000000
# 2014-06-24 06:00:00-07:00     38.286085
# 2014-06-24 12:00:00-07:00    112.287559
# 2014-06-24 18:00:00-07:00     59.009638
# Freq: 6H, dtype: float64
```

**Expected behavior**
There is no difference in results between using Pandas and NumPy

**Versions:**
 - ``pvlib.__version__``: 0.5.1, 0.5.2
 - ``pandas.__version__``: 0.23.3
- `np.__version__`: 1.14.5
 - Python: 3.6.6 |Anaconda, Inc.| (default, Jun 28 2018, 11:27:44) [MSC v.1900 64 bit (AMD64)]

**Additional context**
[Issue is caused by different treatment of `NaN`.](../blob/v0.5.2/pvlib/irradiance.py#L624-L629) [HIDDEN]

### Additional contract requirements

When both GHI and DHI are zero and the resulting intermediate value is undefined, handle that value without replacing other valid intermediate values with zero.
