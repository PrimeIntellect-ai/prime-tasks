raise helpful warning/exception if no columns specified but passed gaze initialized with sample dataframe
## Description of the problem
As #1015 has shown, it can be easy to miss that pixel/position/velocity/etc. columns need to be specified when initializing or loading a `GazeDataFrame`. Otherwise, the processing functions will raise this rather unhelpful exception:

```
AttributeError: n_components must be either 2, 4 or 6 but is None
```

## Description of a solution

1. A more helpful warning right at initialization. This could be something like: `GazeDataFrame includes samples in data, but no column names are specified. Please specify either pixel_columns, position_columns, velocity_columns or acceleration_columns to apply any transformations`.

2. A more helpful exception when applying transformations. This could something like: `no pixel_columns specified. Please specify pixel_columns during initialization to apply pix2deg()`

The wording of my proposed messages can surely be improved further.

### Additional contract requirements

- When a transformation is applied without inferable gaze components, the exception message must start with `Number of components required but no gaze components could be inferred.`
- When `GazeDataFrame.unnest()` is called with an invalid number of gaze components, it raises an `AttributeError` whose message starts with `Number of components required but no gaze components could be inferred.`
- When a `GazeDataFrame` is initialized with data containing more than one row but no gaze-component columns (pixel, position, velocity or acceleration) are specified or auto-detected, a `UserWarning` is emitted whose message starts with `GazeDataFrame contains data but no components could be inferred.`
