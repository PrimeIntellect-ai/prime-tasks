dataset.read_direct fails with ZeroDivisionError when '0 in shape'
Potential regression of #281, or simply related. H5py allows storing of empty arrays where any one of the dimensions can be 0 (e.g., `(0,)`, `(1, 0)`, `(1, 0, 3)`). If this dataset is read using `read_direct`, a `ZeroDivisionError` is thrown.

<details>
    <summary>System version details (click to expand)</summary>
 * Operating System (e.g. Windows 10, MacOS 10.11, Ubuntu 16.04.2 LTS, CentOS 7)
Arch Linux

 * Python version (e.g. 2.7, 3.5)
3.6.0

 * Where Python was acquired (e.g. system Python on MacOS or Linux, Anaconda on
   Windows)
System repositories

 * h5py version (e.g. 2.6)
2.7.0

 * HDF5 version (e.g. 1.8.17)
1.10
</details>

Minimal script:
```python
import h5py
import numpy as np


print(h5py.version.info)

shape = (0,)  # also try (1, 0, 2) or anything with 0 in it
hfile = h5py.File("/tmp/zerodata.h5", "w")
ds = hfile.create_dataset("ds", data=np.zeros(shape))

print("---------------------------------")
print(ds)
print(hfile["ds"])
print(hfile["ds"][:])

dsread = np.zeros(shape)
hfile["ds"].read_direct(dsread)  # division by zero
hfile.close()
```

Output
```
Summary of the h5py configuration
---------------------------------

h5py    2.7.0
HDF5    1.10.0
Python  3.6.0 (default, Jan 16 2017, 12:12:55)
[GCC 6.3.1 20170109]
sys.platform    linux
sys.maxsize     9223372036854775807
numpy   1.12.1

---------------------------------
<HDF5 dataset "ds": shape (0,), type "<f8">
<HDF5 dataset "ds": shape (0,), type "<f8">
[]
Traceback (most recent call last):
  File "zero.py", line 17, in <module>
    hfile["ds"].read_direct(dsread)  # division by zero
  [HIDDEN]
ZeroDivisionError: integer division or modulo by zero
```

### Additional contract requirements

- A valid `Dataset.read_direct(dest, source_sel=None, dest_sel=None)` call reading an empty dataset, including one with a zero-length dimension, must complete without raising `ZeroDivisionError` when the destination shape matches the selected region.
- Shape mismatches must still raise `TypeError`.
