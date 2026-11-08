Is it possible to get Hz * s to reduce?
* unyt version: 1.0.6
* Python version: 3.6.6
* Operating System: MacOS 10.13.6

### Description

I multiplied Hz and seconds and got a Hz * s quantity.
I expected a result without dimension, as in Km / Km.

### What I Did

```
In [281]: (1*u.Hz) * (1*u.s)
Out[281]: unyt_quantity(1.0, 'Hz*s')

In [282]: (1*u.km) / (1*u.km)
Out[282]: unyt_quantity(1.0, '(dimensionless)')

In [286]: ((1*u.Hz) * (1*u.s)).to(u.dimensionless)
Out[286]: unyt_quantity(1.0, '(dimensionless)')
```

### Additional contract requirements

- Add a public method `Unit.simplify()` on `unyt.unit_object.Unit` (also
  reachable as `unyt.Unit`). It takes no arguments and returns a `Unit` in
  which compatible factors have been canceled; the returned unit may carry a
  dimensionless numeric coefficient (for example `100*m` instead of
  `m**2/cm`).
- Add a public method `Unit.as_coeff_unit()` on `unyt.unit_object.Unit`. It
  takes no arguments and returns a tuple `(coefficient, unit)` where
  `coefficient` is a float and `unit` is a `Unit` representing the unit part
  with the dimensionless numeric coefficient removed.
- `str((unyt.kHz * unyt.s ** 2 * unyt.km).simplify())` must equal exactly
  `"1000*km*s"`.
- Products and quotients of arrays and quantities that carry units are
  automatically simplified, so that for example `(1*unyt.Hz) * (1*unyt.s)`
  has dimensionless units.
