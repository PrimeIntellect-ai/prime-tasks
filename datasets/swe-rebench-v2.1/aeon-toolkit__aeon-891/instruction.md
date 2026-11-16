[ENH] support unequal length for RDST
### Describe the feature or idea you want to propose

Implement support for unequal length input for RDST classifier and transformer. Related to the improvement introduced in #820

### Describe your proposed solution

Replicate the changes from #820 and check for additional constraints on the shapelet generation of RDST.

### Describe alternatives you've considered, if relevant

_No response_

### Additional context

_No response_

### Additional contract requirements

- The RDST transformer (`RandomDilatedShapeletTransform`) and classifier (`RDSTClassifier`) accept unequal-length input supplied as a list of 2-D arrays of shape `(n_channels, n_timepoints)` whose `n_timepoints` may differ between series. Fitting and transforming such input must succeed and return one transformed row per input series; fitting and predicting must succeed and return one prediction per input series, and predicting class probabilities must succeed and return one probability row per input series.
- The `RandomShapeletTransform` and `RandomDilatedShapeletTransform` transformers expose a fitted attribute `max_shapelet_length_` holding the maximum actual shapelet length fitted to the training data.
- For `RandomShapeletTransform`, transforming a series shorter than the fitted maximum shapelet length must raise a `ValueError` whose message contains the exact phrase `smaller than the min shapelet length`.
