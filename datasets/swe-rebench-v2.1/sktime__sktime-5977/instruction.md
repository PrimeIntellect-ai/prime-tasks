[BUG] `FourierFeatures` does not work as expected in `ForecastingPipeline`
**Describe the bug**
<!--
A clear and concise description of what the bug is.
-->

Using FourierFeatures in a forecasting pipeline does not produce the same results as using FourierFeatures separately then passing the features to a forecaster. The pipeline produces a flat forecast while the result should not be flat.

**To Reproduce**
<!--
Add a Minimal, Complete, and Verifiable example (for more details, see e.g. https://stackoverflow.com/help/mcve

If the code is too long, feel free to put it in a public gist and link it in the issue: https://gist.github.com
-->

```python
import pandas as pd
import numpy as np

from sktime.forecasting.base import ForecastingHorizon
from sktime.forecasting.compose import ForecastingPipeline, TransformedTargetForecaster
from sktime.forecasting.statsforecast import StatsForecastAutoARIMA
from sktime.transformations.compose import YtoX
from sktime.transformations.series.exponent import SqrtTransformer
from sktime.transformations.series.fourier import FourierFeatures
from sktime.utils.plotting import plot_series
import matplotlib.pyplot as plt


dates = pd.date_range(start="2024-01-01", end="2024-04-01", freq="1H")
calls_per_minute_low = 100 * 60
calls_per_minute_high = 500 * 60
calls = pd.Series(
    index=dates,
    data=np.random.randint(low=calls_per_minute_low, high=calls_per_minute_high, size=len(dates))
)


fh = ForecastingHorizon(values=range(1, 168+1), is_relative=True, freq="H")

arima = StatsForecastAutoARIMA(sp=1,d=0,D=0)

fourier = FourierFeatures(sp_list=[24, 24*7], fourier_terms_list=[10, 5])
fourier.fit(calls)
X_train = fourier.transform(calls)
future = pd.Series(data=1, index=fh.to_absolute_index(calls.index.max()))
X_pred = fourier.transform(future)
pred_arima = arima.fit_predict(y=calls, X=X_train, X_pred=X_pred, fh=fh)

fourierArimax = ForecastingPipeline([
    YtoX(),
    FourierFeatures(sp_list=[24, 24*7], fourier_terms_list=[10, 5]),
    StatsForecastAutoARIMA(sp=1,d=0,D=0),
])

pred_fourierArimax = fourierArimax.fit_predict(y=calls, fh=fh)

fig, ax = plot_series(calls.tail(168), pred_arima, pred_fourierArimax, labels=["calls", "Arima", "FourierArimaxPipeline"])
plt.show()
```

**Expected behavior**
<!--
A clear and concise description of what you expected to happen.
-->

pipeline should produce the same forecast as no pipeline code.

**Additional context**
<!--
Add any other context about the problem here.
-->

Here is a plot for clarity
![image](https://github.com/sktime/sktime/assets/24213087/39930d58-3be4-4e7e-b8d1-75d910d64dee)


**Versions**
<details>

<!--
Please run the following code snippet and paste the output here:

from sktime import show_versions; show_versions()
-->

</details>

<!-- Thanks for contributing! -->
