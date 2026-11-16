get_antenna_redundancies fails to properly group North-South oriented baselines.
This example demonstrates the issue:

```python
import numpy as np
import pyuvdata
import matplotlib.pyplot as plt

eps = 1e-10 # the size of the error induced by pyuvdata ENU <-> ECEF transformations

# antenna positions at corners of a square with two small perturbations
ant_pos = np.array([
    [-eps,1.,0.],
    [1.,1.,0.],
    [eps,0.,0.],
    [1.,0.,0.]
])

ant_nums = np.arange(4)

red_grps, _, _ = pyuvdata.utils.get_antenna_redundancies(ant_nums, ant_pos, tol=0.1)

for grp in red_grps:
    bl_num = grp[0] # get one baseline from each redundant group
    ai, aj = pyuvdata.utils.baseline_to_antnums(bl_num, 4)
    bij = ant_pos[aj] - ant_pos[ai]

    plt.plot(bij[0], bij[1], '.k', ms=10)
plt.ylim(-1.1,1.1)
plt.xlim(-1.1,1.1)
plt.show()
```
produces this figure of baseline positions for this demo array

![redundancy_group_failure](https://user-images.githubusercontent.com/13594524/62745625-e7f43200-ba19-11e9-9787-c3a7420425cc.png)

`red_grps` has 5 groups when there are really only 4. The points at (0, 1) and (0, -1) should be in the same redundant group. This looks like a problem with the initial attempt in `get_antenna_redundancies` to select only half the points.
