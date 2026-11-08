dask.array take issue
I'm getting an error attempting to call da.take(a, axis=1). Sorry I don't have minimal reproducible example, but here's the context:

![image](https://cloud.githubusercontent.com/assets/703554/12915762/41bc6d68-cf25-11e5-8475-efbf21f2bf76.png)

...and here's the stack trace:

```
---------------------------------------------------------------------------
NameError                                 Traceback (most recent call last)
<ipython-input-20-fde38592888e> in <module>()
----> 1 gds = da.take(gd, pop1_sample_indices, axis=1)
      2 gds

/usr/local/lib/python3.5/dist-packages/dask/array/core.py in take(a, indices, axis)
   1851         return _take_dask_array_from_numpy(a, indices, axis)
   1852     else:
-> 1853         return a[(slice(None),) * axis + (indices,)]
   1854
   1855

/usr/local/lib/python3.5/dist-packages/dask/array/core.py in __getitem__(self, index)
    985             return self
    986
--> 987         dsk, chunks = slice_array(out, self.name, self.chunks, index)
    988
    989         return Array(merge(self.dask, dsk), out, chunks, dtype=self._dtype)

/usr/local/lib/python3.5/dist-packages/dask/array/slicing.py in slice_array(out_name, in_name, blockdims, index)
    117     """
    118     index = replace_ellipsis(len(blockdims), index)
--> 119     index = tuple(map(sanitize_index, index))
    120     blockdims = tuple(map(tuple, blockdims))
    121

/usr/local/lib/python3.5/dist-packages/dask/array/slicing.py in sanitize_index(ind)
     53         return ind
     54
---> 55     raise IndexError("Invalid index", i)
     56
     57

NameError: name 'i' is not defined
```

Weird thing is, I don't know why dask is even trying to raise an IndexError, the indices are perfectly valid for the array.

### Additional contract requirements

- `da.take` must accept a pandas Series of integer positional indices and select the requested elements in the order given by the Series, including when `axis=1`.
