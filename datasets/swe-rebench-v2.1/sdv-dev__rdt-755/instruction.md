Categorical reverse transform may crash with `ValueError` for certain dtypes (int64)
### Environment Details
* RDT version: 1.9.0 (latest)
* Python version: Any
* Operating System: Any

### Error Description
Due to certain bugs in SDV (see [SDV issue 1691](https://github.com/sdv-dev/SDV/issues/1691)), the data that is being reverse transformed may erroneously contain null values. That is: There are null values in the transformed data, even though it's supposed to be fully numerical.

If this happens, then the behavior of `reverse_transform` is inconsistent depending on the dtype of the original data

- If the original dtype is a string or a float, then the reverse transform simply allows the null value to pass without any effect
- But if the original dtype is an int, then the reverse transform crashes upon trying to cast the null value to an integer (not allowed by pandas)

### Steps to reproduce

```python
import pandas as pd
import numpy as np

from rdt import HyperTransformer
from rdt.transformers.categorical import UniformEncoder

# original data: categorical with dtype int64
test_data = pd.DataFrame(data={
    'A': [1, 1, 2, 2, 2, 3, 3, 3]
})

ht = HyperTransformer()
ht.set_config({
    'sdtypes': {
        'A': 'categorical',
    },
    'transformers': {
        'A': UniformEncoder()
    }
})

ht.fit(test_data)

# transformed data contains null values
bad_data = pd.DataFrame(data={
    'A': [0.102693, 0.165187, np.nan, 0.311625, 0.654629, 0.854138, 0.704197]
})

ht.reverse_transform(bad_data)
```

Output:
```
ValueError: Cannot convert float NaN to integer
```
[stack_trace.txt](https://github.com/sdv-dev/RDT/files/13814023/stack_trace.txt)


### Expected Behavior
Applies to categorical transformers: `UniformEncoder`, `OrderedUniformEncoder`, `LabelEncoder`, `OrderedLabelEncoder`

- If the dtype is int64 _and_ the reverse transform is crashing (due to null values), then show the user a warning and cast the column to float64 instead. Since float64 is allowed to contain null values, the behavior will at least be more consistent with other dtypes.

```
Warning: There are null values in the transformed data. The reversed transformed data will contain null values of type 'float'.
```

<img width="932" alt="image" src="https://github.com/sdv-dev/RDT/assets/3227804/d3a50a12-2be4-41a5-a1ce-f6022f5b487b">

- If the dtype is something else (float, string), then there is no change to the functionality. However, it would be good to show a warning anyways because it is unexpected to have null values.

```
Warning: There are null values in the transformed data. The reversed transformed data will also contain null values.
```

### Additional contract requirements

- For `UniformEncoder`, `OrderedUniformEncoder`, `LabelEncoder` and `OrderedLabelEncoder`, when the original column is int64 and the data passed to `reverse_transform` contains nulls, `reverse_transform` must not raise an error. It must emit a `UserWarning` that mentions null values and return the column with dtype float64, with the nulls kept as missing values.
- For the same four encoders with a non-integer original dtype, `reverse_transform` on data containing nulls must emit a `UserWarning` that mentions null values, keep the original dtype, and keep the nulls as missing values in the output, with the other values reversed as they are without nulls.
