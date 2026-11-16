[ENH] Consider changing `outlier_norm` default to `True` for Catch22 estimators.
### Describe the feature or idea you want to propose

Catch22 can take significantly longer to calculate based on the max value in the series. Higher values mean longer run time. The `outlier_norm` parameter mitigates this by normalising for the features responsible, but by default it is set to `False`.

### Describe your proposed solution

Evaluate the impact of the parameter for series with low/medium/high values. Based on results, decide whether to change the default or not.

### Describe alternatives you've considered, if relevant

_No response_

### Additional context

This parameter does not exist in the original publication, as all the series were normalised in the paper so this issue was not present.

### Additional contract requirements

- The default value of the `outlier_norm` parameter is `True` for every Catch22 estimator:
  - `Catch22` in `aeon.transformations.collection.feature_based`
  - `Catch22Classifier` in `aeon.classification.feature_based`
  - `Catch22Clusterer` in `aeon.clustering.feature_based`
  - `Catch22Regressor` in `aeon.regression.feature_based`
