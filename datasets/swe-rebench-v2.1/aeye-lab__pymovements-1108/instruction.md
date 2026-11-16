implement `Experiment.from_dict()`
## Description of the problem

It would be nice if the screen and eyetracker arguments in the experiment init could be overloaded to also support dictionaries.

Let's take this dict as an example:

```python
dict_definition = {
    'screen': {
        'height_cm': 30.2,
        'height_px': 1024,
        'width_cm': 38.2,
        'width_px': 1280,
        'distance_cm': 60,
        'origin': 'center',
    },
    'eyetracker': {
        'sampling_rate': 2000,
        'model': 'EyeLink II',
        'vendor': EyeLink',
    },
}
```

Trying to initialize a `DatasetDefinition` with `DatasetDefinition(**dict_definition)` wont' work as `screen` and `eyetracker` are just dicts and not the initialized class objects.

#914 implemented a workaround in its `DatsetDefinition.from_yaml()` method but it would be more elegant to solve this in the `Experiment.__init__()` itself.

## Description of a solution

The `screen` and `eyetracker` arguments in `Experiment.__init__()` should be overloaded to also support dictionaries.
If a dictionary is passed, a `Screen` or `EyeTracker` object should be initialized on the fly.

**EDIT**:

Instead of overloading `Experiment.__init__()`, please implement the method `Experiment.from_dict()`.
