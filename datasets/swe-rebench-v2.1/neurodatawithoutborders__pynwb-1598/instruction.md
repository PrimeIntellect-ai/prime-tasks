[Bug]: IntracellularElectrodeTable.add_recording should not require electrode
### What happened?

`IntracellularElectrodeTable.add_recording` currently requires an `electrode` argument, but this is redundant because the stimulus and/or response objects have an electrode field and the electrode can be easily inferred from those.

### Steps to Reproduce

```python
cCSS = CurrentClampStimulusSeries(
            name="test_cCSS",
            data=np.ones((30,)),
            electrode=electrode_name,
            gain=1.0,
            rate=100_000.,
        )

        cCS = CurrentClampSeries(
            name="test_cCS",
            data=np.ones((30,)),
            electrode=electrode_name,
            gain=1.0,
            rate=100_000.,
        )

        itr = IntracellularRecordingsTable()
        itr.add_recording(stimulus=cCSS, response=cCS)
```


### Traceback

_No response_

### Operating System

macOS

### Python Executable

Python

### Python Version

3.7

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
