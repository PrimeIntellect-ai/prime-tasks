Make the default missing value imputation `'mean'`
### Problem Description
In previous discussions (#606 and #715) we discussed adding a `'random'` imputation strategy instead of `'mean'`. There are good reasons for this; the motivating example was when there is a high percent of missing values.

It is great to have this feature, but we want to leave it as an optional setting that users can choose to turn on. For now, let's **not yet make it the default** -- i.e. let's **keep the default as `'mean'`**.

### Expected behavior
For applicable sdtypes (numerical, datetime), the HyperTransformer should assign transformers with missing value imputation `'mean'`. If the user wants to use the `'random'` strategy, they can always update transformers in the config.

### Additional context
SDV uses the default parameters from RDT. We should finish a more thorough investigation using our demo datasets, etc. to determine whether to change the default to `'random'`.
