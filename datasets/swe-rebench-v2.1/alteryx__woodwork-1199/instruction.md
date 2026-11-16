Mutual information job can fail with certain index types
Mutual information job can fail if index has a logical type that is not included in the types returned by `ww.utils.get_valid_mi_types()`. This is because of the flow in the code. [HIDDEN]

#### Code Sample, a copy-pastable example to reproduce your bug.

```python
import pandas as pd
import woodwork as ww

df = pd.DataFrame({
    "idx": ["A", "B", "C", "D"],
    "int": range(4),
    "cat": [1, 2, 1, 1]
})
df.ww.init(index="idx")
df.ww.mutual_information()
```

```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
/var/folders/b1/hzhmvl_s1xv9n11qgdmzrsw5c63y2l/T/ipykernel_96938/1116556468.py in <module>
----> 1 df.ww.mutual_information()

~/dev/woodwork/woodwork/table_accessor.py in mutual_information(self, num_bins, nrows, include_index, callback)
    941             (perfect dependency).
    942         """
--> 943         mutual_info = self.mutual_information_dict(
    944             num_bins, nrows, include_index, callback
    945         )

~/dev/woodwork/woodwork/accessor_utils.py in wrapper(self, *args, **kwargs)
    205             )
    206             raise WoodworkNotInitError(msg)
--> 207         return method(self, *args, **kwargs)
    208
    209     return wrapper

~/dev/woodwork/woodwork/table_accessor.py in mutual_information_dict(self, num_bins, nrows, include_index, callback)
    903             (perfect dependency).
    904         """
--> 905         return _get_mutual_information_dict(
    906             self._dataframe, num_bins, nrows, include_index, callback
    907         )

~/dev/woodwork/woodwork/statistics_utils.py in _get_mutual_information_dict(dataframe, num_bins, nrows, include_index, callback)
    282
    283     if not include_index and dataframe.ww.index is not None:
--> 284         [HIDDEN]
    285
    286     data = dataframe.loc[:, valid_columns]

ValueError: list.remove(x): x not in list
```

### Additional contract requirements

- A mutual-information call must not fail merely because the configured index has a logical type that is unsupported for mutual-information calculations. With the default index-excluding behavior, the index must remain excluded while other eligible columns remain usable.
