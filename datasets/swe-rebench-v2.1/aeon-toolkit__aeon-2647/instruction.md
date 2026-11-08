[ENH] Itakura parallelogram unequal length support
### Describe the feature or idea you want to propose

Currently Itakura parallelogram doesn't support unequal length time series. It would be nice make it so it does.

### Describe your proposed solution

Current a error is being thrown as when you call the function with unequal length it returns a bounding of all false.
```
@njit(cache=True)
def _itakura_parallelogram(x_size: int, y_size: int, max_slope_percent: float):
    """Itakura parallelogram bounding matrix.

    This code was adapted from tslearn. This link to the original code line 974:
    https://github.com/tslearn-team/tslearn/blob/main/tslearn/metrics/dtw_variants.py
    """
    if x_size != y_size:
        raise ValueError(
            """Itakura parallelogram does not support unequal length time series.
Please consider using a full bounding matrix or a sakoe chiba bounding matrix
instead."""
        )
```

### Describe alternatives you've considered, if relevant

_No response_

### Additional context

_No response_
