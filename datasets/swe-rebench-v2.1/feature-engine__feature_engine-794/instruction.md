yeo-johnson inverse transform throws an erro
```
InvalidIndexError                         Traceback (most recent call last)
File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\series.py:1289, in Series.__setitem__(self, key, value)
   1288 try:
-> 1289     self._set_with_engine(key, value, warn=warn)
   1290 except KeyError:
   1291     # We have a scalar (or for MultiIndex or object-dtype, scalar-like)
   1292     #  key that is not present in self.index.

File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\series.py:1361, in Series._set_with_engine(self, key, value, warn)
   1360 def _set_with_engine(self, key, value, warn: bool = True) -> None:
-> 1361     loc = self.index.get_loc(key)
   1363     # this is equivalent to self._values[key] = value

File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\indexes\range.py:418, in RangeIndex.get_loc(self, key)
    417     raise KeyError(key)
--> 418 self._check_indexing_error(key)
    419 raise KeyError(key)

File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\indexes\base.py:6059, in Index._check_indexing_error(self, key)
   6056 if not is_scalar(key):
   6057     # if key is not a scalar, directly raise an error (the code below
   6058     # would convert to numpy arrays and raise later any way) - GH29926
-> 6059     raise InvalidIndexError(key)

InvalidIndexError: 64      True
682     True
960     True
1384    True
1100    True
        ...
763     True
835     True
1216    True
559     True
684     True
Name: LotArea, Length: 1022, dtype: bool

During handling of the above exception, another exception occurred:

IndexingError                             Traceback (most recent call last)
Cell In [21], line 1
----> 1 train_unt = tf.inverse_transform(train_t)
      2 test_unt = tf.inverse_transform(test_t)

[HIDDEN]

[HIDDEN]
[HIDDEN]
    [HIDDEN]

File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\series.py:1329, in Series.__setitem__(self, key, value)
   1324     raise KeyError(
   1325         "key of type tuple not found and not a MultiIndex"
   1326     ) from err
   1328 if com.is_bool_indexer(key):
-> 1329     key = check_bool_indexer(self.index, key)
   1330     key = np.asarray(key, dtype=bool)
   1332     if (
   1333         is_list_like(value)
   1334         and len(value) != len(self)
   (...)
   1339         #  _where call below
   1340         # GH#44265

File ~\Documents\Repositories\envs\fe_not\lib\site-packages\pandas\core\indexing.py:2662, in check_bool_indexer(index, key)
   2660 indexer = result.index.get_indexer_for(index)
   2661 if -1 in indexer:
-> 2662     raise IndexingError(
   2663         "Unalignable boolean Series provided as "
   2664         "indexer (index of the boolean Series and of "
   2665         "the indexed object do not match)."
   2666     )
   2668 result = result.take(indexer)
   2670 # fall through for boolean

IndexingError: Unalignable boolean Series provided as indexer (index of the boolean Series and of the indexed object do not match).

```

Error can be reproduced by applying inverse_transform to the code we currently have in the user guide as demo

### Additional contract requirements

- `inverse_transform` must successfully inverse-transform DataFrame inputs with non-default row labels without an index-alignment error, while preserving the input row labels and their correspondence to the transformed rows.
