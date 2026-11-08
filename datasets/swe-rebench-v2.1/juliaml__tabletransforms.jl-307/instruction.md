Add support for `missing`  values in `StdFeats` transform
The transform currently fails with `missing` values.

### Additional contract requirements

When a continuous input column contains missing values, the transformed output must retain `missing` at each corresponding row. The observed values in that column must be standardized to approximately zero mean and unit standard deviation.
