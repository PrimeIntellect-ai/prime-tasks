Synthetic data contains all nulls with some RDTs, with min/max enforcement enabled, and null column learning enabled
### Environment Details

Please indicate the following details about the environment in which you found the bug:

* SDV version: 1.17.4 (Latest)
* RDT version:
* Python version: 3.10.0
* Operating System: Google Colab

### Error Description

Generated synthetic data contains only null values when:

- The original column had some null values
- Transformer is updated to either `OptimizedTimestampEncoder` or `UnixTimestampEncoder` with the following parameters:
  - `enforce_min_max_values` is `True`
  - `missing_value_generation` is 'from_column'

### Workaround

Coming soon

### Steps to reproduce

[Link to internal Colab notebook](https://colab.research.google.com/drive/1ksIb5hRVQruPtYumL5Gdza5mImtOXa1p?authuser=1#scrollTo=fII_5DL8El54)

Sample code for just OptimizedTimestampEncoder:

```
import numpy as np
import pandas as pd
from sdv.metadata import Metadata
from sdv.single_table import GaussianCopulaSynthesizer
from rdt.transformers.datetime import OptimizedTimestampEncoder

# Generate data with missing date values
start_date = pd.Timestamp("2023-01-01")
dates = np.array([start_date + pd.Timedelta(days=j) for j in range(100)], dtype="datetime64[ns]")
num_missing = int(100 * 0.2)
missing_indices = np.random.choice(100, num_missing, replace=False)
dates[missing_indices] = np.datetime64("NaT")

data = pd.DataFrame({'date': dates})
metadata = Metadata.detect_from_dataframe(data)

metadata.update_column(
    column_name='date',
    sdtype='datetime',
    table_name='table'
)

# Update transformers
synthesizer = GaussianCopulaSynthesizer(metadata)
synthesizer.auto_assign_transformers(data)

transformer = OptimizedTimestampEncoder(
      missing_value_replacement='mean',
      missing_value_generation='from_column',
      enforce_min_max_values=True)

synthesizer.update_transformers(
      column_name_to_transformer={
          'date': transformer
      }
  )

synthesizer.fit(data)
synthetic_data = synthesizer.sample(100)
synthetic_data.isnull().sum()
```

The last line of code returns 100% null values.

![Image](https://github.com/user-attachments/assets/5c800e4d-3d64-4a18-bf2b-8827dced21f2)
