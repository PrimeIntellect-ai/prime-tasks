Automl: infer problem type from target data
Hello!

I wrote this tiny helper function that tests if a target variable is multiclass or binary for classification problems. Max thought it might be helpful if we added it to EvalML.

```python
def get_problem_type(input_problem_type, target_data):
    """helper function to determine if classification problem is binary or multiclass dependent on target variable values."""
    if input_problem_type == "classification":
        values = target_data.value_counts()
        [HIDDEN]
        else:
            raise ValueError(
                "The target field contains less than two unique values. It cannot be used for modeling."
            )
    return ProblemTypes.REGRESSION
```

### Additional contract requirements

Add a public function `detect_problem_type(y)` in module `evalml.problem_types.utils`, and export it from `evalml.problem_types` so it can be imported as `from evalml.problem_types import detect_problem_type`.

`detect_problem_type(y)` takes a `pd.Series` of target values and returns a member of the `ProblemTypes` enum:

- `ProblemTypes.BINARY` when the target has exactly two distinct values.
- `ProblemTypes.MULTICLASS` when the target has more than two distinct values and either the values are non-numeric or the values are numeric with at most ten distinct values.
- `ProblemTypes.REGRESSION` when the values are numeric and there are more than ten distinct values.

Missing or null entries are ignored when counting distinct values. When fewer than two distinct values remain, raise `ValueError` with a message containing "Less than 2".
