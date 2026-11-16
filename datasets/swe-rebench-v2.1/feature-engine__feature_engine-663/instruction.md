RelativeFeatures: add option not to fail when dividing by zero and instead fill inf values with something

### Additional contract requirements

`RelativeFeatures` provides a `fill_value` option for relative-feature operations involving division. When a reference value is zero, the resulting infinite relative-feature value is replaced with the configured value rather than raising an error. The replacement applies to generated relative-feature values; retained original columns are unchanged. If no `fill_value` is configured, division by zero continues to raise a `ValueError`.
