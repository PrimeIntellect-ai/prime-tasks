Defer processing ConfigDict's handling of default values until they are needed
## Summary

We lack an elegant way to pass configured solvers as config arguments, as is pointed out in #3220.

### Rationale

Many transformations rely on the user being able to pass a *configured* solver as an argument so that that configuration will persist wherever it is used in the transformation (or meta algorithm). Right now we often do that by passing a solver instance, but this is suboptimal since those solver instances will be created on import. (Alternatively, some parts of code take the solver name as the argument and pass an options dictionary separately, but this is rather clunky and difficult to validate.)

### Description

As suggested by @jsiirola, allow this syntax:
```python
CONFIG.declare(
    'solver',
    ConfigValue(
        domain=SolverFactory,
        default='gurobi',
        description="A solver to use to solve the continuous subproblems for "
        "calculating the M values",
    ),
)
```
and don't process the default value until the first time it is needed.

### Additional contract requirements

- `pyomo.common.flags.NOTSET` is a sentinel object. Calling `NOTSET()` returns the `NOTSET` object itself, so `NOTSET() is NOTSET` is true.
- Deferred default processing applies to both `ConfigValue` and `ConfigList`. A default value (including a callable default) is not processed when the configuration entry is declared; it is processed only when the value is first needed (for example, when it is read or when the entry is reset). Explicitly assigning a value does not process the default.
- When a configuration value's default is a class (type) object, displaying the configuration renders that entry as `<class 'type'>`. In particular, a `ConfigDict` declaring `callback` as a `ConfigValue` whose default is a class object displays as exactly `callback: <class 'type'>\n`, and the generated template for that entry (with description `docstr`) is exactly `callback: <class 'type'>  # docstr\n`.


- For `ConfigValue(default=lambda x: 10 * x)`, reading the value without supplying the lambda's required argument must raise `TypeError` with a message matching `r"<lambda>\(\) .* argument"`.
