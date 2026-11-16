The `GaussianNormalizer` should accept distribution names that are consistent with `scipy`
### Problem Description
The [GaussianNormalizer](https://docs.sdv.dev/rdt/transformers-glossary/numerical/gaussiannormalizer) accepts a distribution parameter, where you can provide a string name of the univariate distribution.

The acceptable strings are: `'gaussian'`, `'gamma'`, `'beta'`, `'student_t'`, `'truncated_gaussian'` and `'gaussian_kde'`

These names are **inconsistent** with both of the following:
- The underlying scipy library where the univariates come from and
- The [SDV library](https://docs.sdv.dev/sdv/single-table-data/modeling/synthesizers/gaussiancopulasynthesizer) which uses the same names as scipy.

### Expected behavior
Change the mappings to the following:

- `'norm'` should be used for a Gaussian distribution
- `'truncnorm'` should be used for a truncated Gaussian Distribution
- `'t'` should be used for Student T


### Additional context
In order to keep backwards compatibility, we can still accept the older names. If a user inputs them, internally use the newer names and show a Future Warning.

```python
# example: user inputs 'gaussian' instead of 'norm'
my_transformer = GaussianNormalizer(distribution='gaussian')
```
This ultimately uses the correct distribution but it shows a future warning.
```
FutureWarning: Future versions of RDT will not support 'gaussian' as an option. Please use 'norm' instead.
```
