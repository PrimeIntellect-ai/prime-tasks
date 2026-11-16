Implement `roll`
[HIDDEN]

See https://data-apis.org/array-api/latest/API_specification/generated/signatures.manipulation_functions.roll.html

### Additional contract requirements

`roll` circularly shifts elements by signed integer offsets along the specified axis or axes. The result has the same shape and dtype as the input. When `axis` is omitted, the input is flattened for the shift and the result is restored to the input shape. `shift` and `axis` may be scalars or tuples; omitting `axis` requires a scalar shift and raises `TypeError` for a non-scalar shift, while differing numbers of shifts and axes raise `ValueError`.
