HyperTransformer should ensure that each column is assigned to a different transformer instance
### Problem Description
The HyperTransformer is designed to work by assigning a different transformer _instance_ to each of the columns. Each transformer instance is responsible for (a) learning/saving information about the column during `fit`, and (b) using the saved information during the `transform` and `reverse_transform` phases.

Different information needs to be learned/saved for each column. Therefore, it is not feasible to assign different columns to the same transformer instance.

Currently, the HyperTransformer does not check for this. It allows me to assign the same instance to multiple columns, which can cause misleading error messages and/or data issues later down-the-line, when it is harder to debug.

### Replication
The following code assigns the same instance of `UniformEncoder` to both columns `'A'` and `'B'` in the data.

```python
import pandas as pd
from rdt import HyperTransformer
from rdt.transformers.categorical import UniformEncoder

test_data = pd.DataFrame(data={
    'A': ['yes', 'yes', 'no', 'no', 'no'],
    'B': [True, False, True, True, False] })

# create an instance of the transformer
transformer = UniformEncoder()

# assign the same transformer instance to 'A' and 'B'
ht = HyperTransformer()
ht.set_config({
    'sdtypes': {
        'A': 'categorical',
        'B': 'categorical'
    },
    'transformers': {
        'A': transformer,
        'B': transformer
    }
})
ht.fit_transform(test_data)
```

The following warnings are printed out, but there is nothing indicating that this is due to the same transformer instance:
```
/usr/local/lib/python3.11/dist-packages/rdt/transformers/categorical.py:175: UserWarning:

The data in column 'B' contains new categories that did not appear during 'fit' (0.4625401125705246, 0.6773115734705, 0.2947487449252827, +2 more). Assigning them random values. If you want to model new categories, please fit the data again using 'fit'.

/usr/local/lib/python3.11/dist-packages/rdt/transformers/categorical.py:185: FutureWarning:

Setting an item of incompatible dtype is deprecated and will raise an error in a future version of pandas. Value '[ True False False  True False]' has dtype incompatible with float64, please explicitly cast to a compatible dtype first.
```

And observe how the transformed data isn't fully numerical -- column `'A'` is left with categorical values.

<img width="758" alt="Image" src="https://github.com/user-attachments/assets/bde2b82c-ca91-4a97-a9bb-1f13b707d25a" />

This will cause problems down the line, eg if you are trying to then model this data using Copulas.

### Expected behavior
The HyperTransformer should always check to make that a transformer instance is not shared between different columns. This check should be made every time the config is updated by the user. Namely:
- [`set_config`](https://docs.sdv.dev/rdt/usage/hypertransformer/configuration#set_config) and
- [`update_transformers`](https://docs.sdv.dev/rdt/usage/hypertransformer/configuration#update_transformers)

During both of these updates, the HyperTransformer should check to make sure that the same instance of a transformer is not being duplicated anywhere. If it is, then we should throw an error asking the user to create a new instance.

**Case 1**: Many columns are being set using the same function (`update_transformers` or `set_config`) using the same transformer. Do not update any of the columns and throw an error instead with the first duplicate instance found.

```python
transformer = UniformEncoder()
ht.update_transformers({
  'A': transformer,
  'B': transformer
})
```

```
InvalidConfigError: The same transformer is being assigned to columns ('A') and ('B'). Please create
different transformer objects for each assignment.
```

**Case 2**: If a transformer is being set but we already have the same transformer instance in the config somewhere.
```python
transformer = UniformEncoder()

ht.update_transformers({'A': transformer}) # adds this transformer to the config
ht.update_transformers({'B': transformer}) # same instance is being used on a different column!
```
```
InvalidConfigError: The transformer for column ('B') is already assigned to column ('A'). Please create different
transformer objects for each assignment.
```

### Additional Context
Of course, some transformers themselves work on multi-columns such as [GPSNoiser](https://docs.sdv.dev/rdt/transformers-glossary/deep-data-understanding/gps-coordinates/gpsnoiser#examples). But even in this case, a multi-column transformer can only be used once on a given pair of columns. The error messages can adjust to include the set of columns.

```python
transformer = GPSNoiser(noise_km=10.0)

ht.set_config({
  'sdtypes': {
    'origin_lat': 'latitude',
    'origin_lon': 'longitude',
    'dest_lat': 'latitude',
    'dest_lon': 'longitude'
  },
  'transformers': {
    ('origin_lat', 'origin_lon'): transformer,
    ('dest_lat', 'dest_lon'): transformer
  }
})
```
```
InvalidConfigError: The same transformer is being assigned to columns ('origin_lat', 'origin_lon') and ('dest_lat', 'dest_lon'). Please create
different transformer objects for each assignment.
```
