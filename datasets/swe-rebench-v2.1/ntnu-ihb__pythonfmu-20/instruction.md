Provide start values for variables that requires it
According to the spec, some variables with a given causality/variability must provide a start value. This is currently not the case. At least not automatically.

### Additional contract requirements

A variable requires a start value when any of the following holds:

- its `initial` is `exact` or `approx`, or
- its `causality` is `input` or `parameter`, or
- its `variability` is `constant`.

When a variable requires a start value, its start value is automatically set to the value of the
slave instance's Python attribute whose name matches the variable's name.

Add a public static method `ScalarVariable.requires_start(v) -> bool` in module
`pythonfmu.variables` that reports whether the given variable requires a start value according to
the rule above.
