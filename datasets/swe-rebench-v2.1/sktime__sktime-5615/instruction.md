[BUG] `HierarchyEnsembleForecaster` returns unexpected predictions if data has only one hierarchy level and forecasters specified by node
**Describe the bug**

The `HierarchyEnsembleForecaster` returns unexpected predictions if the hierarchy has only one level and different forecasters are specified per node (`by=node`).


**To Reproduce**
The code snippet below is similar to the examples in the [documentation](https://www.sktime.net/en/latest/api_reference/auto_generated/sktime.forecasting.compose.HierarchyEnsembleForecaster.html) but with only one level instead of two and only 3 bottom nodes instead of 7.

```python
from sktime.forecasting.compose import HierarchyEnsembleForecaster
from sktime.forecasting.naive import NaiveForecaster
from sktime.forecasting.trend import PolynomialTrendForecaster, TrendForecaster
from sktime.utils._testing.hierarchical import _bottom_hier_datagen
y = _bottom_hier_datagen(
        no_bottom_nodes=3,
        no_levels=1,
        random_seed=123
)
y.groupby(["l1_agg"]).sum().index

# Example of by = 'node'
forecasters = [
    ('trend', TrendForecaster(), [("__total")]),
    ('poly', PolynomialTrendForecaster(degree=2), [('l1_node01')]),
]
forecaster = HierarchyEnsembleForecaster(
                forecasters=forecasters,
                by='node', default=NaiveForecaster()
)
forecaster.fit(y, fh=[1, 2, 3])
y_pred = forecaster.predict()
y_pred
```
*Output:*
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th></th>
      <th>passengers</th>
    </tr>
    <tr>
      <th>l1_agg</th>
      <th>timepoints</th>
      <th></th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th rowspan="3" valign="top">__total</th>
      <th>1961-01</th>
      <td>9024.895980</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>9075.494395</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>9126.092810</td>
    </tr>
    <tr>
      <th rowspan="6" valign="top">l1_node01</th>
      <th>1961-01</th>
      <td>497.671704</td>
    </tr>
    <tr>
      <th>1961-01</th>
      <td>432.000000</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>501.352085</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>432.000000</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>505.046482</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>432.000000</td>
    </tr>
    <tr>
      <th rowspan="3" valign="top">l1_node02</th>
      <th>1961-01</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th rowspan="3" valign="top">l1_node03</th>
      <th>1961-01</th>
      <td>1919.395692</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>1919.395692</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>1919.395692</td>
    </tr>
  </tbody>
</table>
</div>

**Expected behavior**
*Output:*
<div>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th></th>
      <th>passengers</th>
    </tr>
    <tr>
      <th>l1_agg</th>
      <th>timepoints</th>
      <th></th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th rowspan="3" valign="top">__total</th>
      <th>1961-01</th>
      <td>9024.895980</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>9075.494395</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>9126.092810</td>
    </tr>
    <tr>
      <th rowspan="3" valign="top">l1_node01</th>
      <th>1961-01</th>
      <td>497.671704</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>501.352085</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>505.046482</td>
    </tr>
    <tr>
      <th rowspan="3" valign="top">l1_node02</th>
      <th>1961-01</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>5893.819230</td>
    </tr>
    <tr>
      <th rowspan="3" valign="top">l1_node03</th>
      <th>1961-01</th>
      <td>1919.395692</td>
    </tr>
    <tr>
      <th>1961-02</th>
      <td>1919.395692</td>
    </tr>
    <tr>
      <th>1961-03</th>
      <td>1919.395692</td>
    </tr>
  </tbody>
</table>
</div>



**Additional context**
The predictions for the node `l1_node01` are duplicated. The first occurrences are the predictions from `PolynomialTrendForecaster`. The second occurrences are predictions of the `NaiveForecaster` which is configured as default. If using two hierarchy levels as in the documentation the predictions are as expected (i.e., no duplicates from the default predictor).

I tried to stay close to the example in the doc. However, maybe I am just using the `HierarchyEnsembleForecaster` class wrong.

**Versions**

System:
    python: 3.11.5 | packaged by conda-forge | (main, Aug 27 2023, 03:35:23) [Clang 15.0.7 ]
executable: ../anaconda3/envs/sktime311/bin/python
   machine: macOS-14.0-x86_64-i386-64bit

Python dependencies:
          pip: 23.2.1
       sktime: 0.24.0
      sklearn: 1.3.0
       skbase: 0.5.1
        numpy: 1.25.2
        scipy: 1.11.2
       pandas: 2.0.3
   matplotlib: 3.7.2
       joblib: 1.3.2
        numba: None
  statsmodels: 0.14.0
     pmdarima: 2.0.3
statsforecast: None
      tsfresh: None
      tslearn: None
        torch: None
   tensorflow: None
tensorflow_probability: None
