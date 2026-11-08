HyperTransformer transforms while fitting and messes up the random seed
### Environment Details

* RDT version: 1.7
* Python version: 3.x
* Operating System: MacOS

### Error Description

While working on #606 , I realized that the `HyperTransformer` transforms twice and moves the seed forward which causes you to get different values after applying `reset_randomization`.

### Steps to reproduce

Running the code below we can see that the count of the test transformer will be `2` instead of `1`.

```python
import numpy as np
import pandas as pd

from rdt import HyperTransformer

df = pd.DataFrame({
    'num': [1, 2, 3, np.nan, np.nan],
    'cat': ['a', 'b', 'c', np.nan, None],
    'datetime': pd.to_datetime(['2021-01-20', '2022-01-10', pd.NaT, pd.NaT, '2021-04-10'])
})

hp = HyperTransformer()

hp.detect_initial_config(df)

from rdt.transformers import BaseTransformer

class TestTransformer(BaseTransformer):
    SUPPORTED_SDTYPES = ['numerical']

    def __init__(self):
        super().__init__()
        self.random_number = 0

    def _fit(self, data):
        return data

    def _transform(self, data):
        self.random_number = np.random.random()
        return data

    def _reverse_transform(self, data):
        return data

testtransformer = TestTransformer()

hp.update_transformers_by_sdtype('numerical', testtransformer)

hp.fit_transform(df)
first_run = hp.field_transformers['num'].random_number

hp.reset_randomization()
hp.transform(df)
second_run = hp.field_transformers['num'].random_number

print(first_run == second_run) # False

# Reset and run again
hp.reset_randomization()
hp.transform(df)
print(second_run == hp.field_transformers['num'].random_number) # True
```
