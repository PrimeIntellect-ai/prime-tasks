[BUG] Off-axis projections and on-axis projections differ for oct-based datasets
### Bug report

**Bug summary**

*Copied from #5059*
OK - I've actually uncovered a funny one.
```python
import numpy as np
import yt
import matplotlib.pyplot as plt
ds = yt.load("output_00080")
p1 = yt.ProjectionPlot(
    ds,
    "x",
    ("gas", "density"),
    center=[0.5] * 3,
    width=.8,
    #weight_field=("gas", "density"),
)
p2 = yt.OffAxisProjectionPlot(
    ds,
    [1, 0, 0],
    ("gas", "density"),
    center=[0.5] * 3,
    width=.8,
    #weight_field=("gas", "density"),
)

# Note: due to our implementation, the off-axis projection will have a
# slightly blurred cell edges so we can't do an exact comparison
v1, v2 = p1.frb["gas", "density"], p2.frb["gas", "density"]

fig = plt.figure()
plt.imshow(v1, origin="lower", norm=plt.matplotlib.colors.LogNorm())
plt.colorbar()
fig.savefig("/tmp/1.png")

fig = plt.figure()
plt.imshow(v2, origin="lower", norm=plt.matplotlib.colors.LogNorm())
plt.colorbar()
fig.savefig("/tmp/2.png")

fig = plt.figure()
plt.imshow(v1 / v2, origin="lower")
plt.colorbar()
fig.savefig("/tmp/3.png")
print(np.median(v1 / v2), np.mean(v1 / v2), np.std(v1 / v2))
```

This returns:
| Projection | Off-axis projection | Difference |
|---|---|---|
|![1](https://github.com/user-attachments/assets/3275e7a0-b10f-437e-b860-d468a5a9259d)|![2](https://github.com/user-attachments/assets/e03988f5-d173-4967-ab5e-587dfb449866)|![3](https://github.com/user-attachments/assets/f3afa354-ce77-4df3-8bfd-10bd17c91553)|

The funny thing is that the ratio between the on-axis and the off-axis projection is equal (within some uncertainties) to `plot_width * 0.5675` (above, `plot_width = 0.8`). This is the case for a RAMSES dataset (here), but the same can be obtained using `fake_random_ds` instead, yielding the same value.

As much as I see how I could have missed a `plot_width` factor, what the heck is `0.5675`?

**Expected outcome**

Both the projection and off-axis projection should be the same map (up to small differences).
This bug was most likely introduced in #4741.


**Version Information**
  * yt version: 4.4 and above

### Additional contract requirements

- The on-axis and off-axis projections of the same field, computed with the
  same `center`, `width` and `weight_field`, must be the same map up to small
  differences. Quantitatively, let `v1` and `v2` be the on-axis and off-axis
  projected values and let `d = (v1 - v2) / (v1 + v2) * 2` be the normalized
  difference. The mean of `d` must satisfy `abs(mean(d)) < 0.1`, and the 10th
  and 90th percentiles of `d` must satisfy `q10 > -0.1` and `q90 < 0.1`.
