PlotMapView resets limits of existing axes to entire model domain
**Describe the bug**
Maybe this is intentional and not a bug, but: PlotMapView resets the matplotlib axes limits to the entire model domain.

**To Reproduce**
Steps to reproduce the behavior:
Run the following code:
```
import numpy as np
import flopy
import matplotlib.pyplot as plt

nrow=30
ncol=20
delr=np.array([100] * ncol)
delc = np.array([100] * nrow)
modelgrid = flopy.discretization.StructuredGrid(nrow=nrow, ncol=ncol, delr=delr, delc=delc)

f, ax = plt.subplots()
ax.axis('scaled')
ax.axis([500, 800, 200, 400])
pmv = flopy.plot.PlotMapView(modelgrid=modelgrid)
pmv.plot_grid()
```

**Expected behavior**
I expect the ax to have an extent specified in ax.axis(): [500, 800, 200, 400]. However, the axes is zoomed out to fit the entire model domain.

**Screenshots**
The outcome of the code above is:
![outcome](https://github.com/modflowpy/flopy/assets/18527362/85107875-e4bd-4096-8cf1-4a4c6e2be74c)

While the desired outcome would be:
![expected_outcome](https://github.com/modflowpy/flopy/assets/18527362/e97b4c2b-9ea3-46ed-931c-9406576f36df)


**Possible solution**
[HIDDEN]

### Additional contract requirements

- `flopy.plot.PlotMapView` exposes a public `extent` property returning the model domain extent as `(xmin, xmax, ymin, ymax)`.
- When plotting on axes with autoscaling disabled, preserve their existing limits. When autoscaling is enabled, set the axes limits to the model-domain extent.
