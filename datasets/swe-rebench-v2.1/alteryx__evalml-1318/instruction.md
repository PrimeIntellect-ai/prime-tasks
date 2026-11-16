explain_predictions_best_worst does not support custom index in the target
Found during the blitz.

Repro:

```python
from evalml.demos import load_breast_cancer
from evalml.pipelines import BinaryClassificationPipeline
from evalml.model_understanding import explain_predictions_best_worst, explain_predictions

class RfPipeline(BinaryClassificationPipeline):
    component_graph = ["Random Forest Classifier"]

X, y = load_breast_cancer()
y.index = range(100, 100 + len(y))

pl = RfPipeline({})

explain_predictions_best_worst(pl, X, y)
```
