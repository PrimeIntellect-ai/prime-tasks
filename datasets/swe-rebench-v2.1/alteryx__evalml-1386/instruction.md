Implement problem type for time series regression
Currently we have a convention that each defined objective maps to a single problem type. In the future we will add objectives that are only valid for time series regression, but we would also want to evaluate the pipeline on "standard" regression metrics like MSE or MAE.

If we follow our existing convention, we would have to add `MSETimeSeries`, `MAETimeSeries` classes. This would lead to 2x the number of objectives with 100% duplication!

@dsherry and I agreed that this wasn't the most maintainable solution so we agreed on the following **breaking** change:

* Let `problem_type` in `RegressionObjective`, `BinaryClassificationObjective`, `MulticlassClassficationObjective`  be a list
* Add a method to `ObjectiveBase` called `is_defined_for_problem_type` that determines if the objective is defined for the given problem type

### Additional contract requirements

- `ProblemTypes` exposes `TIME_SERIES_REGRESSION`, and `ProblemTypes.all_problem_types` includes it.
- When AutoML search is configured for time-series regression, it accepts regression objectives whose supported problem types include time-series regression, including the standard regression objectives.
- The class attribute that holds the supported problem types is named `problem_types` (plural) and is a `list` on `ObjectiveBase` subclasses.
- `RegressionObjective.problem_types` contains both `ProblemTypes.REGRESSION` and `ProblemTypes.TIME_SERIES_REGRESSION`, so standard regression objectives (for example `MSE`, `MAE`, `R2`) are defined for time-series regression.
- `BinaryClassificationObjective.problem_types` contains `ProblemTypes.BINARY` and `MulticlassClassificationObjective.problem_types` contains `ProblemTypes.MULTICLASS`; neither is defined for `ProblemTypes.TIME_SERIES_REGRESSION`.
- `ObjectiveBase.is_defined_for_problem_type(problem_type)` returns `True` when `problem_type` is in the objective's `problem_types` list and `False` otherwise.
