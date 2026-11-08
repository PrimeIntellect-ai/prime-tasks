XML cube output fails for numpy < 2.3
## 🐛 Bug Report
Changes made in #6518 result in cube.xml() failing for numpy versions < 2.3

## How To Reproduce
With HEAD of Iris main and numpy==2.2.6:

```python
from iris.cube import Cube
import numpy as np

print(np.__version__)

cube = Cube(data=np.ones(10), standard_name='air_pressure')
print(cube.xml())
```

Error message:
```
  File ".../python3.12/site-packages/numpy/_core/arrayprint.py", line 361, in get_printoptions
    opts['legacy'] = {
                     ^
KeyError: '2.2'
```

## Expected behaviour
Shouldn't error.
Looks like some defensive conditionals are needed for checking numpy version?

## Environment
numpy==2.2.6

### Additional contract requirements

- The module `iris.cube` must expose the module-level name `NP_PRINTOPTIONS_LEGACY`.
