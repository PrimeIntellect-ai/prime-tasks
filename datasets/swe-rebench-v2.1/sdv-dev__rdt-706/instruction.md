The `GaussianNormalizer` should accept `uniform` distributions
### Problem Description
The [GaussianNormalizer](https://docs.sdv.dev/rdt/transformers-glossary/numerical/gaussiannormalizer) accepts a `distribution` parameter, where you can provide a string name of the univariate distribution. For example:

```python
my_transformer = GaussianNormalizer(distribution='beta')
```

The available distributions are: `'gaussian'`, `'gamma'`, `'beta'`, `'student_t'`, `'truncated_gaussian'` and `'gaussian_kde'`

### Expected behavior
We should also accept `'uniform'` as a possible parameter. When selected, this should use the copulas [UniformUnivariate distribution](https://github.com/sdv-dev/Copulas/blob/master/copulas/univariate/uniform.py#L9).

### Additional context
If you're only using RDT, then instead of supplying the distribution as a string name, you can also directly input a class. This also does not work for uniform distributions.

```python
from copulas import univariate

my_transformer = GaussianNormalizer(distribution=univariate.Uniform)
```

### Additional contract requirements

A Copulas `UniformUnivariate` class or instance may also be provided directly as the `distribution` argument.
