target_scitype for SupervisedPipelines
Hello everyone,

I think we could add a `target_scitype` directive for SupervisedPipelines.

```julia

LinearRegressor = @load LinearRegressor pkg=MLJLinearModels verbosity = 0
pipe = (X -> coerce(X, :age=>Continuous)) |> ContinuousEncoder() |> LinearRegressor()
target_scitype(pipe)
```

will result in Unknown.

The following should work and happy to try and make the change if your concern is somewhere else:

```julia

[HIDDEN]
```

### Additional contract requirements

- For a supervised pipeline, `target_scitype` must return the same value as `target_scitype` on its supervised component.
