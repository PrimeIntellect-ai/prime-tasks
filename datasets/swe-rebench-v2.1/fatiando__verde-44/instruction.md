Metagridder class to chain operations
The scikit-learn `Pipeline` allows transformations of the Jacobian to be chained with a final estimator at the end. That's fine if you want to chain a scaling operation or PCA. When gridding, we usually want to remove a trend from the data itself, not the Jacobian.

The `Chain` class will take a list of gridder classes and apply them in succession. Each new gridder will fit the residuals from the previous gridder. When predicting, the predictions of each component are summed:

```python
grd = Chain([('trend', Trend(degree=2)), ('grid', ScipyGridder())])
grd.fit(coordinates, data, weights) # fits ScipyGridder on the residuals of Trend
grd.predict(coordinates)  # sums the predictions
grd.grid() # Make a grid of the summed predictions
trend = grd.named_steps['trend'].grid() # Make a grid of the trend only
```

This is a convenient way of adding trends to all our gridders but keeping some level of control on the user side. It will also enable using the same code when implementing equivalent layers in `harmonica`.

### Additional contract requirements

- The `Chain` class is defined in the module `verde.chain` (importable as `verde.chain.Chain`).
- A `Chain` instance exposes the list of `('name', estimator)` pairs it was constructed with as a public `steps` attribute.
- `Chain.fit` accepts an optional `weights` argument that defaults to `None`.
- After fitting, a `Chain` exposes the final residuals as a public `residual_` attribute.
- After fitting, a `ScipyGridder` exposes the residuals `data - predict(coordinates)` as a public `residual_` attribute.
- Supplied weights do not alter the interpolation fit performed by `ScipyGridder`.
- When weights are supplied to `ScipyGridder.fit`, it emits exactly one `UserWarning` with the exact message `ScipyGridder does not support weights and they will be ignored.`
