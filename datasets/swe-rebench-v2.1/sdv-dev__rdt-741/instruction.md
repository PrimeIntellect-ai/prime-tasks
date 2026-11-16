Add enforce_min_max_values to datetime transformers
### Problem Description

_As a user, I'd like my data to be within the same bounds as the original data since out of bounds data might not make sense logically (eg. someone is born on a day that hasn't happened yet).

### Expected behavior

- Add a `enforce_min_max_values` parameter to the `UnixTimestampEncoder` and `OptimizedTimestampEncoder`. This can be a boolean the same way as the [FloatFormatter](https://github.com/sdv-dev/RDT/blob/main/rdt/transformers/numerical.py#L31C14-L31C14) has it.
- We can learn the min and max values in the fit.
- We can clip the values back during `reverse_transform`.
