ENH: Allow to plot weighted KDEs.
### Feature Type

- [X] Adding new functionality to pandas

- [ ] Changing existing functionality in pandas

- [ ] Removing existing functionality in pandas


### Problem Description

The current implementation does not currently allow to plot weighted KDEs.

### Feature Description

Estimation of the PDF is currently done via [scipy.stats.gaussian_kde](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.gaussian_kde.html#scipy.stats.gaussian_kde) which allows for a parameter `weights`.
[pandas.DataFrame.plot.kde](https://pandas.pydata.org/docs/reference/api/pandas.DataFrame.plot.kde.html) should accept this parameter as well.

### Alternative Solutions

[HIDDEN]

### Additional Context

_No response_

### Additional contract requirements

- `Series.plot.kde` and `DataFrame.plot.kde` accept a `weights` argument with one weight per observation.
- The weights change the estimated density: the drawn curve is the weighted kernel density estimate of the data, i.e. the same values scipy's weighted `gaussian_kde` gives for those data and weights, and it differs from the unweighted estimate.
