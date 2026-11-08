BMI and request of scalar variables
### Wflow version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have checked that this bug exists on the latest version of Wflow.


### Reproducible Example

`BMI.get_var_itemsize(model, "lateral.land.alpha_pow")`

### Current behaviour

```
{"status":"ERROR","error":"Wflow BMI get_var_itemsize failed
exception =
MethodError: no method matching view(::Float64, ::UnitRange{Int64}
```

### Desired behaviour

Should give the item size (8) back. The error is thrown because a `view` is applied on a Float64 in `BMI.get_value_ptr(model, name)`. For now, decided to not exchange scalar variables through BMI (there are only a few model parameters defined on a scalar grid).

### Additional Context

_No response_

### Additional contract requirements

The decision above to stop exchanging scalar variables through BMI applies to every BMI
function, including metadata queries. In particular, the item-size result requested above
is not provided: `BMI.get_var_itemsize(model, "lateral.land.alpha_pow")` raises an
`ErrorException` with the message
`"lateral.land.alpha_pow not listed as variable for BMI exchange"` instead of returning
`8`. Scalar variables are also absent from `BMI.get_input_var_names(model)`.

The BMI grid identifiers are: `0` reservoir, `1` lake, `2` drain, `3` river, `4` land
(x-direction staggered grid), `5` land (y-direction staggered grid), `6` land (nodes).
Grids `0`, `1` and `2` have grid type `"points"`; grids `3`, `4`, `5` and `6` have grid
type `"unstructured"`. All grids `0`-`6` have grid rank `2`.
