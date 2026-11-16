numpy.clip is now a ufunc which unit doesn't know about
* unyt version: 2.3.0
* Python version: 3.7
* NumPy version: 1.17
* Operating System: macOS

### Description

In NumPy 1.17 they made `numpy.clip` a ufunc which has 3 inputs. Currently, we do not support any ufuncs with 3 inputs.

Currently this breaks volume rendering tasks which use sigma clipping in yt if NumPy 1.17 is installed. See https://github.com/yt-project/yt/issues/2313

### Code for reproduction

```python
import yt
import numpy as np
a = yt.YTArray(np.random.uniform(size=10), "cm")
a.clip(0.4,  0.6)
```

gives:

```pycon
---------------------------------------------------------------------------
RuntimeError                              Traceback (most recent call last)
<ipython-input-1-335caf0515a5> in <module>
      2 import numpy as np
      3 a = yt.YTArray(np.random.uniform(size=10), "cm")
----> 4 a.clip(0.4,  0.6)

~/miniconda3/lib/python3.7/site-packages/numpy/core/_methods.py in _clip(a, min, max, out, casting, **kwargs)
    130     else:
    131         return _clip_dep_invoke_with_casting(
--> 132             um.clip, a, min, max, out=out, casting=casting, **kwargs)
    133
    134 def _mean(a, axis=None, dtype=None, out=None, keepdims=False):

~/miniconda3/lib/python3.7/site-packages/numpy/core/_methods.py in _clip_dep_invoke_with_casting(ufunc, out, casting, *args, **kwargs)
     83     # try to deal with broken casting rules
     84     try:
---> 85         return ufunc(*args, out=out, **kwargs)
     86     except _exceptions._UFuncOutputCastingError as e:
     87         # Numpy 1.17.0, 2019-02-24

~/Source/unyt/unyt/array.py in __array_ufunc__(self, ufunc, method, *inputs, **kwargs)
   1707             raise RuntimeError(
   1708                 "Support for the %s ufunc with %i inputs has not been"
-> 1709                 "added to unyt_array." % (str(ufunc), len(inputs))
   1710             )
   1711         if unit is None:

RuntimeError: Support for the <ufunc 'clip'> ufunc with 3 inputs has not been added to unyt_array.
```
