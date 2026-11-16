[BUG] BaseSeriesTransformer has no _check_y
### Describe the bug

the base class series transformer calls a method _check_y which does not exist

### Steps/Code to reproduce the bug

```python
    @final
    def fit(self, X, y=None, axis=1):
        """Fit transformer to X, optionally using y if supervised.

        State change:
            Changes state to "fitted".

        Parameters
        ----------
        X : Input data
            Time series to fit transform to, of type ``np.ndarray``, ``pd.Series``
            ``pd.DataFrame``.
        y : Target variable, default=None
            Additional data, e.g., labels for transformation
        axis : int, default = 1
            Axis of time in the input series.
            If ``axis == 0``, it is assumed each column is a time series and each row is
            a time point. i.e. the shape of the data is ``(n_timepoints,
            n_channels)``.
            ``axis == 1`` indicates the time series are in rows, i.e. the shape of
            the data is ``(n_channels, n_timepoints)`.``axis is None`` indicates
            that the axis of X is the same as ``self.axis``.

        Returns
        -------
        self : a fitted instance of the estimator
        """
        # skip the rest if fit_is_empty is True
        if self.get_tag("fit_is_empty"):
            self._is_fitted = True
            return self
        if self.get_tag("requires_y"):
            if y is None:
                raise ValueError("Tag requires_y is true, but fit called with y=None")
        # reset estimator at the start of fit
        self.reset()
        X = self._preprocess_series(X, axis=axis, store_metadata=True)
        if y is not None:
            self._check_y(y)
        self._fit(X=X, y=y)
        self._is_fitted = True
        return self
```


### Expected results

function exists

### Actual results

no function exists

### Versions

_No response_

### Additional contract requirements

- `BaseSeriesTransformer` provides a `_check_y(y)` method that validates a supplied
  target `y`. A valid `y` is a 1-dimensional `np.ndarray` or a `pd.Series`.
- If `y` is neither a `np.ndarray` nor a `pd.Series`, or if it is a `np.ndarray`
  with more than one dimension, `_check_y` raises a `TypeError`.
- `fit` calls `_check_y` whenever `y` is not `None`, so calling `fit(X, y)` with an
  invalid `y` raises a `TypeError`.
