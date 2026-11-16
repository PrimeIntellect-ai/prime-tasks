Hashing : possible work-around for avoiding to rely on `np.dtype('float64').__class__` being picklable
From a failure in the scikit-learn tests using the numpy development wheels (1.20.dev) https://github.com/scikit-learn/scikit-learn/pull/17707#issuecomment-650212919.

The error is related to `joblib.Memory` argument hashing and its special dtype treatment:
https://github.com/joblib/joblib/blob/ac0f1528ffec9cd53cabbafaca887ac880697862/joblib/hashing.py#L222-L235

This comes from the fact that `np.dtype('float64').__class__` is not picklable in numpy dev:

```py
import pickle

import numpy as np


print('numpy version:', np.__version__)
dt = np.dtype('float64')
print('class: ', dt.__class__)
try:
    pickle.dumps(dt.__class__)
    print('Can pickle dt.__class__')
except Exception as exc:
    print('Exception while pickling dt.__class__')
    print(exc)
```

Output numpy-dev:
```
numpy version: 1.20.0.dev0+be8ab91
class:  <class 'numpy.dtype[float64]'>
Exception while pickling dt.__class__
Can't pickle <class 'numpy.dtype[float64]'>: attribute lookup dtype[float64] on numpy failed
```

Ouptut numpy 1.19.0:
```
numpy version: 1.19.0
class:  <class 'numpy.dtype'>
Can pickle dt.__class__
```

I opened https://github.com/numpy/numpy/issues/16692 to discuss whether this could be fixed in numpy.

Maybe we could use something else in the hash (for example the fully qualified class name of the dtype? Maybe `.descr` is enough actually?). One annoying side-effect is that this would change the hash and cause recomputations for `joblib.Memory` caches when you update numpy. At the same time the changes in numpy dtype (in numpy master) will very likely cause the same recomputations anyway ...

cc @ogrisel, @pierreglaser

Context: #239 #251
