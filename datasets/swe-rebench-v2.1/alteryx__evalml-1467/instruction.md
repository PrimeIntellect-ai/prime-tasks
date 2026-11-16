For some datasets, percent_better_than_baseline_all_objectives is huge because baseline values are infinitesimal
I tested the `percent_better_than_baseline_all_objectives` values on a few datasets and found that `ExpVariance` on two of them was enormous. On `retail_data.csv` it's `1.4857769515459812e+18`.

Turns out this is because the cv objective scores for the baseline was infinitesimal:

```python
for scores in automl.results['pipeline_results'][0]['cv_data']:
    print(scores['all_objective_scores']['ExpVariance'])
```

```
0.0
0.0
1.1102230246251565e-16
```

With `evalml 0.13.2` these were all zero.

Now, obviously there's variability in this kind of thing, but it seems like `1.1102230246251565e-16` is a rounding error, not a real, valid value for this metric.

Here's the reproducer:

```python
import evalml
from evalml import AutoMLSearch
import pandas as pd

data = pd.read_csv('datasets/retail/retail_data.csv')
data = data.drop(['cancelled'], axis=1)

y = data['total']
X = data.drop(['total'], axis=1)

automl = AutoMLSearch(problem_type="regression", objective="Root Mean Squared Error", max_iterations=3)
automl.search(X, y)

# oh, I miss Scala
if automl.data_check_results is not None:
    for boom in automl.data_check_results:
        print(boom)

print(f'pipline 2 ExpVariance: {automl.results["pipeline_results"][2]["percent_better_than_baseline_all_objectives"]["ExpVariance"]}')


for scores in automl.results['pipeline_results'][0]['cv_data']:
    print(f'cv ExpVariance: {scores["all_objective_scores"]["ExpVariance"]}')

```

### Additional contract requirements

- For `ExpVariance.calculate_percent_difference`, return NaN for `(score=0, baseline_score=1e-10)`, `(score=1e-9, baseline_score=0)`, and `(score=0, baseline_score=0)`; for `(score=0, baseline_score=1e-9)`, return approximately `-100`.
