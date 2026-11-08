[Bug]: nwbfile.add_trial_column does not allow extra kwargs
### What happened?

`NWBFile.add_trial_column` is a shortcut for `nwbfile.trials.add_column`. `nwbfile.trials.add_column` allows extra keyword args to be passed, which are then passed to the constructor of `col_cls`. This is useful when the custom VectorData subclass has additional arguments. `NWBFile.add_trial_column` does not allow extra keyword args to be passed, so certain custom VectorData subclasses cannot be initialized.

### Steps to Reproduce

```python
nwbfile.add_trial_column(name="HED", hed_version="8.2.0", description="temp", col_cls=HedTags, data=[])
```


### Traceback

```python
TypeError: NWBFile.add_trial_column: unrecognized argument: 'hed_version'
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

lower version (unsupported)

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
