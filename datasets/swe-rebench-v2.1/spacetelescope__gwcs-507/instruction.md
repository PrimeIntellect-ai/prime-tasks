UnitConversionError when using pixel_to_world
I'm a bit confused as to why the standard WCS API seems to exhibit a different behavior than calling the object directly. I'm running the example from the documentation here:
https://gwcs.readthedocs.io/en/latest/gwcs/points_to_wcs.html#fitting-a-wcs-to-input-pixels-sky-positions

No prior experience with GWCS so I don't know if this is expected? And if it is, what am I expected to provide as an unit of a pixel and how?

```python
import astropy.units as u
import numpy as np
from astropy.coordinates import SkyCoord
from gwcs import wcs_from_points

xy = (np.array([2810.156, 2810.156,  650.236, 1820.927, 3425.779, 2750.369,
                212.422, 1146.91 ,   27.055, 2100.888,  648.149,   22.212,
                2003.314,  727.098,  248.91 ,  409.998, 1986.931,  128.925,
                1106.654, 1502.67 ]),
      np.array([1670.347, 1670.347,  360.325,  165.663,  900.922,  700.148,
                1416.235, 1372.364,  398.823,  580.316,  317.952,  733.984,
                339.024,  234.29 , 1241.608,  293.545, 1794.522, 1365.706,
                583.135,   25.306]))

ra, dec = (np.array([246.75001315, 246.75001315, 246.72033646, 246.72303144,
                     246.74164072, 246.73540614, 246.73379121, 246.73761455,
                     246.7179495 , 246.73051123, 246.71970072, 246.7228646 ,
                     246.72647213, 246.7188386 , 246.7314031 , 246.71821002,
                     246.74785534, 246.73265223, 246.72579817, 246.71943263]),
           np.array([43.48690547,  43.48690547,  43.46792989,  43.48075238,
                     43.49560501,  43.48903538,  43.46045875,  43.47030776,
                     43.46132376,  43.48252763,  43.46802566,  43.46035331,
                     43.48218262,  43.46908299,  43.46131665,  43.46560591,
                     43.47791234,  43.45973025,  43.47208325,  43.47779988]))

radec = SkyCoord(ra, dec, unit=(u.deg, u.deg))
proj_point = SkyCoord(246.7368408, 43.480712949, frame = 'icrs', unit = (u.deg,u.deg))
gwcs_obj = wcs_from_points(xy, radec, proj_point)

print(gwcs_obj(1, 1))
print(gwcs_obj.pixel_to_world(1, 1))
```

```bash
 ~ $: python test_gwcs.py
(246.7119478955359, 43.46214449707893)
Traceback (most recent call last):
  File "test_gwcs.py", line 31, in <module>
    print(gwcs_obj.pixel_to_world(1, 1))
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/gwcs/api.py", line 300, in pixel_to_world
    return self(*pixels, with_units=True)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/gwcs/wcs.py", line 358, in __call__
    result = transform(*args, **kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1127, in __call__
    outputs = self._generic_evaluate(evaluate, inputs, fill_value, with_bbox)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1089, in _generic_evaluate
    outputs = evaluate(_inputs)
              ^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3289, in evaluate
    return self._evaluate(*_inputs, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3317, in _evaluate
    leftval = self.left(*args, **kw)
              ^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1127, in __call__
    outputs = self._generic_evaluate(evaluate, inputs, fill_value, with_bbox)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1089, in _generic_evaluate
    outputs = evaluate(_inputs)
              ^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3289, in evaluate
    return self._evaluate(*_inputs, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3317, in _evaluate
    leftval = self.left(*args, **kw)
              ^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1127, in __call__
    outputs = self._generic_evaluate(evaluate, inputs, fill_value, with_bbox)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1089, in _generic_evaluate
    outputs = evaluate(_inputs)
              ^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3289, in evaluate
    return self._evaluate(*_inputs, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3332, in _evaluate
    return self.right(*leftval, **kw)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1127, in __call__
    outputs = self._generic_evaluate(evaluate, inputs, fill_value, with_bbox)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1089, in _generic_evaluate
    outputs = evaluate(_inputs)
              ^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3289, in evaluate
    return self._evaluate(*_inputs, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 3324, in _evaluate
    leftval = self.left(*(args[: self.left.n_inputs]), **kw)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 417, in __call__
    new_call = make_function_with_signature(
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 394, in __call__
    return super(cls, self).__call__(*inputs, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1127, in __call__
    outputs = self._generic_evaluate(evaluate, inputs, fill_value, with_bbox)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 1089, in _generic_evaluate
    outputs = evaluate(_inputs)
              ^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/core.py", line 976, in evaluate
    return self.evaluate(*_inputs, *parameters)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/polynomial.py", line 1186, in evaluate
    result = self.multivariate_horner(x, y, invcoeff)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/modeling/polynomial.py", line 1293, in multivariate_horner
    r2 = y * (r0 + r1 + r2)
              ~~~^~~~
  File "...python3.11/site-packages/astropy/units/quantity.py", line 696, in __array_ufunc__
    raise e
  File "...python3.11/site-packages/astropy/units/quantity.py", line 641, in __array_ufunc__
    converters, unit = converters_and_unit(function, method, *inputs)
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "...python3.11/site-packages/astropy/units/quantity_helper/converters.py", line 199, in converters_and_unit
    raise UnitConversionError(
astropy.units.core.UnitConversionError: Can only apply 'add' function to dimensionless quantities when other argument is not a quantity (unless the latter is all zero/infinity/nan).
```
