Move the _learn_rounding_digits of the FloatFormatter into a helper
### Problem Description

Currently, the method to learn the rounding of a column, `_learn_rounding_digits`, is defined inside the `FloatFormatter`.
We would like to move it into a helper file so other transformers can use it.

### Additional context
* The tests should be also moved
* The method is defined here:
https://github.com/sdv-dev/RDT/blob/c3c86acc50b3c9165f95bd45f698874f5491c9ea/rdt/transformers/numerical.py#L95

### Additional contract requirements

Expose the rounding-learning behavior as `rdt.transformers.utils.learn_rounding_digits(data)`, accepting a pandas Series and returning the inferred number of decimal places or `None` when no safe rounding precision can be inferred. The helper must be reusable independently of `FloatFormatter`.
