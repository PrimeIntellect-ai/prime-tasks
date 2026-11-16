[ENH] Implement Yeo-Johnson Series Transformer
### Describe the feature or idea you want to propose

a long time ago I experimented with the Yeo-Johnson regressor transform.

https://ieeexplore.ieee.org/document/1716845

Yeo-Johnson is an extension of Box-Cox that allows xero and negative regressor values. We have an implementation of Box Cox, it would be nice to include Yeo-Johnson


### Describe your proposed solution

either extend Box Cox once it is moved into series tranformers, or implement a new BaseSeriesTransformer

### Describe alternatives you've considered, if relevant

_No response_

### Additional context

_No response_

### Additional contract requirements

- Add a public class `YeoJohnsonTransformer` in the module
  `aeon.transformations.series._yeojohnson`.
- `YeoJohnsonTransformer()` can be constructed without arguments.
- The transformer provides a `fit_transform(X)` method that fits the
  transformation to the series `X` and returns the transformed series as a
  NumPy array.
- After fitting, the attribute `_lambda` holds the fitted Yeo-Johnson lambda
  value.
- When no lambda value is supplied, `_lambda` is exactly equal to the lambda
  value returned by `scipy.stats.yeojohnson` for the input data.
- The transformed values match those returned by `scipy.stats.yeojohnson` for
  the same input data.
