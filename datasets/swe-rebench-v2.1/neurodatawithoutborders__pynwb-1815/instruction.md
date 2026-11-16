[Feature]: Support stimulus_template column in IntracellularRecordingsTable
### What would you like to see added to PyNWB?

See https://github.com/NeurodataWithoutBorders/nwb-schema/pull/545

### Is your feature request related to a problem?

_No response_

### What solution would you like?

Update StimulusTable to support the new optional column

### Do you have any interest in helping implement the feature?

Yes.

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this change was not already [requested](https://github.com/NeurodataWithoutBorders/pynwb/issues)?

### Additional contract requirements

The optional `stimulus_template` column must be able to store a reference to a TimeSeries used as a recording's stimulus template. Recording rows must remain addable when this optional column exists and no template reference is supplied.
