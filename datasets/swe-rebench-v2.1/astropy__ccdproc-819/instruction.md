Error with Numpy 2.0.0rc1
I'm running into the following error with Numpy 2.0.0rc1:

```
    from .extern.bitfield import bitfield_to_boolean_mask as _bitfield_to_boolean_mask
.tox/py311-ccdproc/lib/python3.11/site-packages/ccdproc/extern/bitfield.py:56: in <module>
    MAX_UINT_TYPE = np.maximum_sctype(np.uint)
.tox/py311-ccdproc/lib/python3.11/site-packages/numpy/__init__.py:397: in __getattr__
    raise AttributeError(
E   AttributeError: `np.maximum_sctype` was removed in the NumPy 2.0 release. Use a specific dtype instead. You should avoid relying on any implicit mechanism and select the largest dtype of a kind explicitly in the code.
```
