BUG: ActivityType comparison and serialization issues
### Stravalib version checks

- [X] I have tested this in a new clean environment with only stravalib and core python files.

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pypi.org/project/stravalib/) of stravalib.

- [X] I have confirmed this bug exists on the [main branch](https://github.com/stravalib/stravalib) of stravalib.


### What operating system are you seeing the problem on?

Mac

### What version of python or you running?

```python
3.10.10
```


### Reproducible Example

```python
from stravalib.model import SummaryActivity

a = SummaryActivity.model_validate({'type': 'Run'})
a.type == 'Run'
# Expecting True, but returns False
```


### Issue Description

An activity's `type` attribute is of type `RelaxedActivityType`, but (since the pydantic v2 bump) doesn't behave as a `Literal[str]` anymore. This leads to subtle but potentially dangerous bugs, as seen above. This is a breaking change in 2.0 that we didn't document.

### Expected Behavior

`SummaryActivity.type` should return a type comparable with the previously used `Literal[]`, i.e., something that can be compared to `str` types and should be serialized as `str`.

### Your environment

Not appliccable

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- `SummaryActivity.type` must serialize to a plain `str`. Concretely, for an
  activity created via `SummaryActivity.model_validate({"type": "Run"})`, both
  `activity.model_dump()["type"]` and `activity.model_dump(mode="json")["type"]`
  must be the built-in `str` value `"Run"` (not a `RelaxedActivityType` instance).
