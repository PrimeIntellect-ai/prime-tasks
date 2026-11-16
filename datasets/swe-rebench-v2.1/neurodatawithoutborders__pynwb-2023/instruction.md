[Bug]: OpticalSeries distance, orientation, and field of view should be optional
### What happened?

The current schema says that these fields should be optional:
https://github.com/NeurodataWithoutBorders/nwb-schema/blob/dev/core/nwb.image.yaml#L131

The docval for `OpticalSeries.__init__` says that they are required:
https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/src/pynwb/image.py#L321

### Steps to Reproduce

```python
Try to create an OpticalSeries without optional fields
```


### Traceback

_No response_

### Operating System

macOS

### Python Executable

Conda

### Python Version

3.10

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
