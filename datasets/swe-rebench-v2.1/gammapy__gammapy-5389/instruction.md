LabelMapAxis re-orders labels
**Gammapy version**
v1.1

**Bug description**
When instancing a `LabelMapAxis` the labels are re-ordered / sorted. This is problematic because it should keep the order, that corresponds to the  data.

**Expected behavior**
Do not re-order / sort the labels.

**To Reproduce**
```python
import numpy as np
from gammapy.maps import LabelMapAxis

labels = np.array([3, 2, 1, 4, 5])
print(labels)
print(LabelMapAxis(labels).center)
```
Which prints:
```
[3 2 1 4 5]
[1 2 3 4 5]
```
