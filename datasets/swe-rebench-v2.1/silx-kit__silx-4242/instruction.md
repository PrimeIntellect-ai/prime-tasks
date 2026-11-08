silx.io.h5py_utils does not catch some exceptions with libhdf5 v1.14.x
There's been a change of error message in libhdf5 `H5Oopen`:
* 1.12.x (version embedded h5py wheel <=3.9): `"Unable to open object"`
* 1.14.x (version embedded h5py wheel >=3.10): `"Unable to synchronously open object"`

This makes the retry machinery to fail.
To reproduce with 2 ipython sessions:

```
In [1]: import h5py
In [2]: f = h5py.File("test.h5", "w")
In [3]: f.flush()
```

```
In [1]: import h5py; from silx.io import h5py_utils
In [2]: @h5py_utils.retry(retry_timeout=1, retry_period=0.1)
   ...: def read():
   ...:     with h5py.File("test.h5", locking=False) as f:
   ...:         print("try read data")
   ...:         return f["data"][()]
   ...:
In [3]: read()
```
-> `KeyError: "Unable to synchronously open object (object 'data' doesn't exist)"`

This works as expected with h5py 3.9
