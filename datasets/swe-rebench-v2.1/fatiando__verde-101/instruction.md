Add a Components class for multicomponent data
If we want to grid multicomponent data, we can use something like `Vector2D` to grid them jointly or we can use a `Spline` for each component separately. In this case, there is no way to put them in a `Chain` with `BlockReduce` or `Trend`. Also, `VectorTrend` is doing this for trend estimation.

A better approach would be to have a meta-gridder `Components` that takes multiple estimators and fits each one to a given data component. It would be a generalization of `VectorTrend` and would replace it.

This is how the usage would look:

```python
grd = Chain([
    ('mean', BlockReduce(np.mean, spacing=1),
    ('trend', Components([Trend(degree=1), Trend(degree=2)])),
    ('spline', Components([Spline(), Spline()]))
])
grd.fit(coordinates, (data_east, data_north))
# Access each gridder separately
trend_east = grd.named_steps['trend'].components[0].grid()
```

### Additional contract requirements

- Add a public class `Components` in the module `verde.components`.
- `Components(components)` takes a sequence (list or tuple) of estimator/gridder instances, one per data component, and stores it in the public `components` attribute.
- `Components.fit(coordinates, data, weights=None)` fits each estimator to the matching data component and returns the fitted `Components` instance. `data` must be a tuple of arrays, one per component; if it is not a tuple, a `ValueError` is raised. If `weights` is given, it must be a tuple of arrays, one per component; if it is not a tuple, a `ValueError` is raised.
- `Components.predict(coordinates)` returns a tuple of prediction arrays, one per component, in the same order as the estimators were given.
- `Components` is a gridder and supports the standard gridder interface, including `score(coordinates, data, weights=None)`.
