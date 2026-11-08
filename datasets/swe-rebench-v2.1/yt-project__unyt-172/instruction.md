unyt_array.in_units() casts complex numbers to real losing imaginary part
* unyt version: 2.7.2
* Python version: 3.8.5
* Operating System: Ubuntu 18.04

### Description
Attempted to convert unit of a complex valued array.

### What I Did

```
>>> from unyt import Ω, F, Hz
>>> freq = [1j, 1j*10]*Hz
>>> arr = 1/(Ω*F*freq)
>>> arr.to("dimensionless")
.../numpy/core/_asarray.py:83:ComplexWarning: Casting complex values to real discards the imaginary part
return array(a, dtype, copy=False, order=order)
unyt_array([0., 0.], dtype=float128, units='dimensionless')
```

[HIDDEN]

As a workaround, I can use `unyt_array.in_base()` and then check for `dimensionless`.

### Additional contract requirements

- Unit conversions of complex-valued arrays must preserve their imaginary components rather than cast the values to real.
- For the dimensionless conversion shown above, the resulting array values must compare exactly equal to `np.asarray([-1j, -1j * 0.1])`.
