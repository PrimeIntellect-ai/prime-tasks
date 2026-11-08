[BUG] Error in `inverse-variance` method of `AutoEnsembleForecaster`
**Describe the bug**
When fitting the `AutoEnsembleForecaster` forecaster with exogenous data using the `inverse-variance` method, an error is raised. [HIDDEN] (see [here](https://github.com/alan-turing-institute/sktime/blob/4164639e1c521b112711c045d0f7e63013c1e4eb/sktime/forecasting/compose/_ensemble.py#L190)).

**To Reproduce**

```python
from sktime.datasets import load_longley
from sktime.forecasting.arima import ARIMA
from sktime.forecasting.compose import AutoEnsembleForecaster

forecasters = [
    ("forecaster_1", ARIMA()),
    ("forecaster_2", ARIMA()),
]

y, X = load_longley()


ensemble_forecaster = AutoEnsembleForecaster(
    forecasters=forecasters, method="inverse-variance"
)
ensemble_forecaster.fit(y, X)
```

This code snippet has the following output:

```
Traceback (most recent call last):
  File "test.py", line 16, in <module>
    ensemble_forecaster.fit(y, X)
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/_base.py", line 270, in fit
    self._fit(y=y_inner, X=X_inner, fh=fh)
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/compose/_ensemble.py", line 190, in _fit
    [HIDDEN]
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/_meta.py", line 72, in _predict_forecasters
    return [forecaster.predict(fh=fh, X=X) for forecaster in self.forecasters_]
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/_meta.py", line 72, in <listcomp>
    return [forecaster.predict(fh=fh, X=X) for forecaster in self.forecasters_]
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/_base.py", line 325, in predict
    y_pred = self._predict(fh=fh, X=X_inner)
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/adapters/_pmdarima.py", line 76, in _predict
    return self._predict_fixed_cutoff(fh_oos, X=X)
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/sktime/forecasting/base/adapters/_pmdarima.py", line 178, in _predict_fixed_cutoff
    result = self._forecaster.predict(
  File "/Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/lib/python3.8/site-packages/pmdarima/arima/arima.py", line 785, in predict
    raise ValueError('X array dims (n_rows) != n_periods')
ValueError: X array dims (n_rows) != n_periods
```

**Expected behavior**

The enseble forecaster should run without error and summarize the forecasters based on the inverse error variance of their predictions.

**Additional context**
<!--
Add any other context about the problem here.
-->

**Versions**
<details>

System:
    python: 3.8.9 (default, Oct 16 2021, 12:00:06)  [Clang 12.0.0 (clang-1200.0.32.29)]
executable: /Users/anhoang/Projekte/2022/Daimler/Chronos/chronos/.venv/bin/python
   machine: macOS-11.6-x86_64-i386-64bit

Python dependencies:
          pip: 22.1.2
   setuptools: 63.2.0
      sklearn: 1.1.1
       sktime: 0.13.0
  statsmodels: 0.13.2
        numpy: 1.22.4
        scipy: 1.8.1
       pandas: 1.4.3
   matplotlib: 3.5.2
       joblib: 1.1.0
        numba: 0.56.0
     pmdarima: 1.8.5
      tsfresh: 0.19.0
</details>

<!-- Thanks for contributing! -->

### Additional contract requirements

- With exogenous data, `AutoEnsembleForecaster` using `method="inverse-variance"` must fit and make predictions without error.
