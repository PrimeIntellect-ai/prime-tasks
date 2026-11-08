Add `InSample` resampling strategy
When you want to train on all specified data and test on the same data.

So,

```julia
e = evaluate(model, X, y, resampling=InSample(), measure=l1)
e.measurement[1]
```

is equivalent to:

```julia
mach = machine(model, X, y) |> fit!
yhat = predict(mach, X)
l2(yhat, y)
```

Which is even more convenient when there is battery measures to be evaluated.

### Additional contract requirements

For each measure passed to `evaluate`, the reported measurement is that measure applied to predictions from a model fitted on the evaluation observations. In the example above, the equivalent manual calculation applies `l1` (the requested measure), not `l2`; a battery of measures reports the corresponding result for each requested measure.
