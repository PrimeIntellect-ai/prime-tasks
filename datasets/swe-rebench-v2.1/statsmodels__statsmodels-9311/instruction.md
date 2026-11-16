Zivot-Andrews Test with data type float64 modifies dataset used in the test
#### Describe the bug

Using the Zivot-Andrews Test (from statsmodels.tsa.stattools.zivot_andrews) with a variable with type float64 modifies the values of the variable used in the test (in the dataframe). This doesn't happen with variables with type int32, for example.

This is a problem because it changes the values in the dataframe being used for statistical analysis, considering that the Zivot-Andrews test is done before fitting a model.

#### Code Sample, a copy-pastable example if possible


```python
import pandas as pd
import numpy as np
import statsmodels.api as sm
from statsmodels.tsa.stattools import zivot_andrews

sm.show_versions()

# Create a range of years from 1990 to 2023 for the index
years = pd.date_range(start='1990-01-01', end='2023-12-31', freq='AS')
# Create a DataFrame with variable years as the index
df = pd.DataFrame(index=years)
# Set the values for the variable
df['variable1'] = np.where(df.index.year <= 2002, 10, 20)
df['variable2'] = np.where(df.index.year <= 2002, 10, 20)
df.info()

# Zivot-Andrews test with data with type int32
zivot_andrews(df['variable1'])
zivot_andrews(df['variable1'],regression = 'c')

# Zivot-Andrews test with data with type float64
df=df.astype(float)
zivot_andrews(df['variable1'])
zivot_andrews(df['variable1'],regression = 'c')

```

#### Expected Output

To keep the same dataframe after using the zivot_andrews function.

#### Output of ``import statsmodels.api as sm; sm.show_versions()``

<details>

INSTALLED VERSIONS
------------------
Python: 3.11.5.final.0

statsmodels
===========

Installed: 0.14.0 (C:\ProgramData\anaconda3\Lib\site-packages\statsmodels)

Required Dependencies
=====================

cython: Not installed
numpy: 1.24.3 (C:\ProgramData\anaconda3\Lib\site-packages\numpy)
scipy: 1.11.1 (C:\ProgramData\anaconda3\Lib\site-packages\scipy)
pandas: 2.0.3 (C:\ProgramData\anaconda3\Lib\site-packages\pandas)
    dateutil: 2.8.2 (C:\ProgramData\anaconda3\Lib\site-packages\dateutil)
patsy: 0.5.3 (C:\ProgramData\anaconda3\Lib\site-packages\patsy)

Optional Dependencies
=====================

matplotlib: 3.7.2 (C:\ProgramData\anaconda3\Lib\site-packages\matplotlib)
    backend: module://matplotlib_inline.backend_inline
cvxopt: Not installed
joblib: 1.2.0 (C:\ProgramData\anaconda3\Lib\site-packages\joblib)

Developer Tools
================

IPython: 8.15.0 (C:\ProgramData\anaconda3\Lib\site-packages\IPython)
    jinja2: 3.1.2 (C:\ProgramData\anaconda3\Lib\site-packages\jinja2)
sphinx: 5.0.2 (C:\ProgramData\anaconda3\Lib\site-packages\sphinx)
    pygments: 2.15.1 (C:\ProgramData\anaconda3\Lib\site-packages\pygments)
pytest: 7.4.0 (C:\ProgramData\anaconda3\Lib\site-packages\pytest)
virtualenv: Not installed

</details>
