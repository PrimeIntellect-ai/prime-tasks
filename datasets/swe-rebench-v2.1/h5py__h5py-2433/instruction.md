External link files are opened with file locking enabled even if main file is opened with locking disabled
<details><summary>Summary of the h5py configuration</summary>

```
h5py    3.11.0  # current master
HDF5    1.14.4
Python  3.11.2 (main, Mar 13 2023, 12:18:29) [GCC 12.2.0]
sys.platform    linux
sys.maxsize     9223372036854775807
numpy   2.0.0rc2
cython (built with) 3.0.10
numpy (built against) 2.0.0rc2
HDF5 (built against) 1.14.4
```

</details>

We ran into an issue when accessing external links with HDF5's file locking disabled.
The target file of the external link is always opened with file locking enabled even if the main file was opened with file locking disabled, while one would expect to use consistent file access properties.

This has been first raised to the HDFGroup (see: https://forum.hdfgroup.org/t/external-link-and-file-locking-disabled-issue/12012) and fixed in libhdf5 v1.14.4.

[HIDDEN]

https://github.com/h5py/h5py/blob/902e32c3fdc06f1e0feaa29717df83e92953dc2a/h5py/_hl/base.py#L129-L135


<details><summary>Script to reproduce the issue</summary>

```python
import multiprocessing
import time
import h5py

def create_files():
    with h5py.File("linked.h5", "w") as h5f:
        h5f["data"] = (1, 2, 3)

    with h5py.File("main.h5", "w") as h5f:
        h5f["data"] = (3, 2, 1)
        h5f["link"] = h5py.ExternalLink("linked.h5", "/data")


def read():
    with h5py.File("main.h5", "r", locking=False) as h5f:
        print("data:", h5f["/data"][()])
        print("link:", h5f["/link"][()])


if __name__ == "__main__":
    print("* Create files")
    create_files()
    print("* Open files in append mode")
    main = h5py.File("main.h5", "a")
    linked = h5py.File("linked.h5", "a")
    print("* Read from subprocess")
    context = multiprocessing.get_context("spawn")
    process = context.Process(target=read)
    process.start()
    time.sleep(1)
```

</details>

Also, while looking at this issue, I found an issue in the values of `H5F_close_degree_t` enum which differs from libhdf5 ones:

- libhdf5's [H5Fpublic.h](https://github.com/HDFGroup/hdf5/blob/d3f5e07b1eea230c7ab340ac9fe24dffa8406355/src/H5Fpublic.h#L114-L119) and [version from 23 years ago](https://github.com/HDFGroup/hdf5/blob/d28fd08f4a9593bd8bb51ebc17b8b6555b3885cd/src/H5Fpublic.h#L72-L85):

```
typedef enum H5F_close_degree_t {
    H5F_CLOSE_DEFAULT = 0, /**< Use the degree pre-defined by underlying VFD */
    H5F_CLOSE_WEAK    = 1, /**< File closes only after all opened objects are closed */
    H5F_CLOSE_SEMI    = 2, /**< If no opened objects, file is closed; otherwise, file close fails */
    H5F_CLOSE_STRONG  = 3  /**< If there are opened objects, close them first, then close file */
} H5F_close_degree_t;
```

- h5py: https://github.com/h5py/h5py/blob/902e32c3fdc06f1e0feaa29717df83e92953dc2a/h5py/api_types_hdf5.pxd#L117-L121


I'll prepare a PR to fix the enum and to propose ways to solve this issue for discussion.

### Additional contract requirements

The public `h5py.h5f` close-degree constants must have the same numeric values as their corresponding libhdf5 constants: `CLOSE_DEFAULT` is 0, `CLOSE_WEAK` is 1, `CLOSE_SEMI` is 2, and `CLOSE_STRONG` is 3.
