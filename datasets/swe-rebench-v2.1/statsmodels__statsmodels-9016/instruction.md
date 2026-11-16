`plot_pacf` default `lags` raises with a small sample
#### Describe the bug

When the parameter `lags` is not specified in `statsmodels.graphics.tsaplots.plot_pacf`, the value which is computed by default causes the function to raise a `ValueError` due to `nlags` being more than 50% of the sample size.

The limitation of 50% of the sample size should be applied when computing default `nlags`.

#### Code Sample, a copy-pastable example if possible


```python
import pandas as pd
from statsmodels.graphics.tsaplots import plot_pacf

df = df = pd.DataFrame(
    index=[pd.Timestamp.now() + pd.Timedelta(seconds=i) for i in range(10)],
    columns=["a"],
    data=list(range(10))
)
plot_pacf(df)
```
```traceback
File /tmp/venv/lib/python3.11/site-packages/statsmodels/graphics/tsaplots.py:353, in plot_pacf(x, ax, lags, alpha, method, use_vlines, title, zero, vlines_kwargs, **kwargs)
    351     acf_x = pacf(x, nlags=nlags, alpha=alpha, method=method)
    352 else:
--> 353     acf_x, confint = pacf(x, nlags=nlags, alpha=alpha, method=method)
    355 _plot_corr(
    356     ax,
    357     title,
   (...)
    364     **kwargs,
    365 )
    367 return fig

File /tmp/venv/lib/python3.11/site-packages/statsmodels/tsa/stattools.py:1009, in pacf(x, nlags, method, alpha)
   1007     nlags = min(int(10 * np.log10(nobs)), nobs // 2 - 1)
   1008 if nlags >= x.shape[0] // 2:
-> 1009     raise ValueError(
   1010         "Can only compute partial correlations for lags up to 50% of the "
   1011         f"sample size. The requested nlags {nlags} must be < "
   1012         f"{x.shape[0] // 2}."
   1013     )
   1015 if method in ("ols", "ols-inefficient", "ols-adjusted"):
   1016     efficient = "inefficient" not in method

ValueError: Can only compute partial correlations for lags up to 50% of the sample size. The requested nlags 9 must be < 5.
```
<details>

**Note**: As you can see, there are many issues on our GitHub tracker, so it is very possible that your issue has been posted before. Please check first before submitting so that we do not have to handle and close duplicates.

**Note**: Please be sure you are using the latest released version of `statsmodels`, or a recent build of `main`. If your problem has been fixed in an unreleased version, you might be able to use `main` until a new release occurs.

**Note**: If you are using a released version, have you verified that the bug exists in the main branch of this repository? It helps the limited resources if we know problems exist in the current main branch so that they do not need to check whether the code sample produces a bug in the next release.

</details>


If the issue has not been resolved, please file it in the issue tracker.

#### Expected Output
The limitation of 50% of the sample size should be applied when computing default `nlags`.

See for example https://github.com/datamole-ai/edvart/pull/154 for a workaround.

#### Output of ``import statsmodels.api as sm; sm.show_versions()``

<details>

INSTALLED VERSIONS
------------------
Python: 3.11.3.final.0
OS: Linux 6.5.3-1-MANJARO #1 SMP PREEMPT_DYNAMIC Wed Sep 13 12:21:35 UTC 2023 x86_64
byteorder: little
LC_ALL: None
LANG: en_US.UTF-8

statsmodels
===========

Installed: 0.14.0 /tmp/venv/lib/python3.11/site-packages/statsmodels)

Required Dependencies
=====================

cython: Not installed
numpy: 1.24.4 (/tmp/venv/lib/python3.11/site-packages/numpy)
scipy: 1.10.1 (/tmp/venv/lib/python3.11/site-packages/scipy)
pandas: 1.5.3 (/tmp/venv/lib/python3.11/site-packages/pandas)
    dateutil: 2.8.2 (/tmp/venv/lib/python3.11/site-packages/dateutil)
patsy: 0.5.3 (/tmp/venv/lib/python3.11/site-packages/patsy)

Optional Dependencies
=====================

matplotlib: 3.7.3 (/tmp/venv/lib/python3.11/site-packages/matplotlib)
    backend: module://matplotlib_inline.backend_inline
cvxopt: Not installed
joblib: 1.3.2 (/tmp/venv/lib/python3.11/site-packages/joblib)

Developer Tools
================

IPython: 8.12.2 (/tmp/venv/lib/python3.11/site-packages/IPython)
    jinja2: 3.1.2 (/tmp/venv/lib/python3.11/site-packages/jinja2)
sphinx: 7.1.2 (/tmp/venv/lib/python3.11/site-packages/sphinx)
    pygments: 2.16.1 (/tmp/venv/lib/python3.11/site-packages/pygments)
pytest: 7.1.3 (/tmp/venv/lib/python3.11/site-packages/pytest)
virtualenv: Not installed

</details>
