pass_row parameter should be an input to the field_update step to support functions
# Summary

In the `field_update` step, the `pass_row` parameter is set to `False` by default, except for `formula` which sets it to `True` before calling the `table.convert()` from petl. We should allow this parameter to be set to `True` for `functions` as well for the same reasons that `formula` sets it to `True`.
