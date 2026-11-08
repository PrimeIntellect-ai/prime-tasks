MASE requires y_train
Training time series regression pipelines results in the failure `Mean Absolute Scaled Error encountered AttributeError with message ('NoneType' object has no attribute 'values')`

Repro:
```python
import pandas as pd
import evalml
from evalml.automl import AutoMLSearch
from evalml.preprocessing import split_data

df = pd.read_csv('~/Downloads/DailyDelhiClimateTrain.csv')
X = df.drop(["meantemp"], axis=1)
y = df["meantemp"]
time_index = "date"

problem_configuration = {
    "max_delay": 52,
    "gap": 0,
    "forecast_horizon": 7,
    "time_index": time_index,
}
problem_type = "time series regression"
X_train, X_holdout, y_train, y_holdout = split_data(
    X, y, problem_type=problem_type
)
automl = AutoMLSearch(
    X_train,
    y_train,
    problem_type=problem_type,
    problem_configuration=problem_configuration,
)
automl.search(interactive_plot=False)
```

[HIDDEN]

### Additional contract requirements

When scoring a time-series regression pipeline with the Mean Absolute Scaled Error objective, the supplied training target must be available to scoring so the objective can compute its score without failing because `y_train` is missing.
