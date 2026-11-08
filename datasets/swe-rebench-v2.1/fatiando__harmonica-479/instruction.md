Inverted sign in upward derivative filter
**Description of the problem:**
<!--
Please be as detailed as you can when describing an issue. The more information
we have, the easier it will be for us to track this down.
-->

The upward derivative returned has an inverted sign. It looks OK when inspecting plots because a lot of us are used to the sign convention of positive downwards. But since we use heights (and thus positive upward), the sign should be the opposite of what we expect. This is meant to improve consistency between small-scale and global data (which often has a "radial" component that is positive upward).

The fix should be relatively simple. [HIDDEN]

**Full code that generated the error**
<!--
Include any data files or inputs required to run the code. It really helps if
we can run the code on our own machines.
-->

```python
import harmonica as hm
import verde as vd
import numpy as np
import matplotlib.pyplot as plt

model = [
    [35e3, 40e3, 50e3, 55e3, -6e3, -1e3],
]
magnetization = [
    hm.magnetic_angles_to_vec(20, -40, 15),
]
inc, dec = -40, 15
fe, fn, fu = hm.magnetic_angles_to_vec(1, inc, dec)
region = [0, 100e3, 0, 80e3]
coordinates = vd.grid_coordinates(region, spacing=500, extra_coords=1000)

be, bn, bu = hm.prism_magnetic(coordinates, model, np.transpose(magnetization), field="b")
anomalia = fe * be + fn * bn + fu * bu

grid = vd.make_xarray_grid(coordinates, anomalia, data_names="tfa", extra_coords_names="upward")
grid["d_up"] = hm.derivative_upward(grid.tfa)

fig, axes = plt.subplots(1, 2, layout="constrained", figsize=(10, 3))
grid.tfa.plot(ax=axes[0])
grid.d_up.plot(ax=axes[1])
```

**Full error message**


This produces the following result:

![image](https://github.com/fatiando/harmonica/assets/290082/8ec8fbf2-b293-434c-96b1-d7f0d6036124)

If we use positive upward, then the positive parts of the anomaly should be decreasing towards 0 (negative derivative) and the negative parts of the anomaly should be increasing towards 0 (positive derivative).


**System information**

* Operating system: Linux
* Python installation (Anaconda, system, ETS): Miniforge
* Version of Python: 3.11
* Version of this package: current main ([bbaf5a1](https://github.com/fatiando/harmonica/commit/bbaf5a191c7a3ccf9835a2d3b565be26a3500d26))
* If using conda, paste the output of `conda list` below: Not using conda.

<details>
<summary>Output of conda list</summary>
<pre>

PASTE OUTPUT OF CONDA LIST HERE

</pre>
</details>
