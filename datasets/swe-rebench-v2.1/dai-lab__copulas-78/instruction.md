Error on vine copulas sampling - 'Edge' object has no attribute 'index'
* Copulas version: 0.2.0
* Python version: 3.6.5
* Operating System: Xubuntu 18.04

### Description

Got and exception while trying to sample data using Vine Copulas with Regular Tree.

### What I Did

``` python
import pandas as pd
from copulas.multivariate import VineCopula, TreeTypes

X = pd.DataFrame([
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1]
])
vine = VineCopula(TreeTypes.REGULAR)
vine.fit(X)
vine.sample()
```

which gave me the following exception:

```
copulas/multivariate/vine.py in sample(self, num_rows)
    165                             if (edge.L == current and edge.R == visited[0]) or\
    166                                (edge.R == current and edge.L == visited[0]):
--> 167                                 current_ind = edge.index
    168                                 break
    169                         else:

AttributeError: 'Edge' object has no attribute 'index'
```
