FloatFormatter does not round the data correctly for integer columns when using _set_fitted_parameters
### Environment Details

* RDT version: 1.12.3

### Error Description

We can't currently set the `rounding_digits` attribute of the `FloatFormatter` to 0 with `_set_fitted_parameters`. It seems to be because of the following line:
https://github.com/sdv-dev/RDT/blob/bb3262e2fa88264dbc8b4d9f497dddd87adee0f2/rdt/transformers/numerical.py#L239


### Steps to reproduce
In the code below the `reverse_transformed_data` will not be rounded while `rounding_digits=0`
```python
import pandas as pd
import numpy as np
from rdt.transformers import FloatFormatter, NullTransformer

data = pd.DataFrame({
    'col 1': 100 * np.random.random(10),
})
transformer = FloatFormatter()
transformer._set_fitted_parameters(
    column_name='col 1',
    null_transformer=NullTransformer(),
    rounding_digits=0,
    dtype='float',
)

reverse_transformed_data = transformer.reverse_transform(data)
reverse_transformed_data
```
