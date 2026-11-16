[Feature]: Enhance NWBHDF5IO to check NWB version
### What would you like to see added to PyNWB?

NWBHDFI5O should check (either on __init__ or when calling read) what the version of the file is an raise and error if the  NWB version is 1.x

### Is your feature request related to a problem?

This is related to https://github.com/NeurodataWithoutBorders/nwbinspector/issues/329 Currently NWBHDF5IO fails on read for NWB 1.x files with an error message that is hard to debug.

### What solution would you like?

* Add function to get the nwb version from a file to NWBHDF5IO
* Either on __init__ or when calling read, NWBHDF5IO should check the version and raise an error if the version is 1.x

### Do you have any interest in helping implement the feature?

Yes.

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this change was not already [requested](https://github.com/NeurodataWithoutBorders/pynwb/issues)?

### Additional contract requirements

- `NWBHDF5IO` exposes a public property `nwb_version` that returns a 2-tuple: the raw `nwb_version` string stored in the file and a parsed representation of that string as a tuple of integers and strings. When the `nwb_version` attribute is absent (for example, on a newly created empty file), `nwb_version` returns `(None, None)`. For the raw version string `bad_version`, the parsed tuple is `("bad", "version")`.
- `NWBHDF5IO.read` accepts an optional keyword argument `skip_version_check` (bool, default `False`). When `skip_version_check` is `False`, `read` raises `TypeError` if the file's `nwb_version` attribute is missing, with the message `Missing NWB version in file. The file is not a valid NWB file.`, and raises `TypeError` if the parsed major version is below 2, with the message `NWB version 1.0.5 not supported. PyNWB supports NWB files version 2 and above.` (where `1.0.5` is the raw version string of the file). When `skip_version_check` is `True`, these version checks are bypassed. `read` returns the `NWBFile` container.
