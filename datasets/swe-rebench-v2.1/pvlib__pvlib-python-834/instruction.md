Implement IEC 61853 module temperature model
The Faiman module temperature model is used in IEC 61853.  It conceptually not much different from others, but uses slightly different parameters.

### Additional contract requirements

Add a public function `faiman(poa_global, temp_air, wind_speed=1.0, u0=25.0, u1=6.84)` in module `pvlib.temperature`.

- `poa_global`: total incident irradiance [W/m²]; numeric scalar or array-like (list, `numpy.ndarray`, `pandas.Series`).
- `temp_air`: ambient dry-bulb temperature [°C]; numeric scalar or array-like, broadcastable with `poa_global`.
- `wind_speed`: wind speed at module height [m/s]; numeric scalar or array-like, default 1.0.
- `u0`: combined heat-loss coefficient [W/(m²·°C)]; scalar or array-like, default 25.0.
- `u1`: wind-dependent heat-loss coefficient [(W/(m²·°C))/(m/s)]; scalar or array-like, default 6.84.

All vector inputs must have the same length; scalars are broadcast. The return value is a numeric scalar, `numpy.ndarray`, or `pandas.Series` of module temperature in degrees Celsius, matching the shape/broadcast of the input arrays. The result is NaN exactly where an input is NaN.
