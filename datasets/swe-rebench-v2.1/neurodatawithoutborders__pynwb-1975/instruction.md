[Bug]: PatchClampSeries gain is optional in the schema but required in pynwb
### What happened?

I believe the schema indicates that `PatchClampSeries.gain` is an optional dataset with a quantity of 0 or 1:
https://github.com/NeurodataWithoutBorders/nwb-schema/blob/35889d36dfa088ec4a3614fa0350c02ced4a068c/core/nwb.icephys.yaml#L28-L31

while `pynwb` requires that gain is provided as an input to create a `PatchClampSeries` object:
https://github.com/NeurodataWithoutBorders/pynwb/blob/e938202b257e44c5536dc35476d55aa98e57d18d/src/pynwb/icephys.py#L109-L112

As a result, nwb files created without PatchClampSeries `gain` specified cannot be read with pynwb.


### Steps to Reproduce

Create a file in matnwb without specifying the gain for VoltageClampSeries, then try reading the file in with pynwb


### Traceback

```python
(root/acquisition/vcs GroupBuilder {'attributes': {'comments': 'no comments', 'description': 'no description', 'namespace': 'core', 'neurodata_type': 'VoltageClampSeries', 'object_id': '59cfdc19-9576-488a-a158-c7781f4e33f5', 'stimulus_description': 'N/A', 'sweep_number': 15}, 'groups': {}, 'datasets': {'capacitance_slow': root/acquisition/vcs/capacitance_slow DatasetBuilder {'attributes': {'unit': 'farads'}, 'data': 1e-10}, 'data': root/acquisition/vcs/data DatasetBuilder {'attributes': {'conversion': 1e-12, 'offset': 0.0, 'resolution': nan, 'unit': 'amperes'}, 'data': <Closed HDF5 dataset>}, 'resistance_comp_correction': root/acquisition/vcs/resistance_comp_correction DatasetBuilder {'attributes': {'unit': 'percent'}, 'data': 70.0}, 'starting_time': root/acquisition/vcs/starting_time DatasetBuilder {'attributes': {'rate': 20000.0, 'unit': 'seconds'}, 'data': 123.6}}, 'links': {'electrode': root/acquisition/vcs/electrode LinkBuilder {'builder': root/general/intracellular_ephys/elec0 GroupBuilder {'attributes': {'namespace': 'core', 'neurodata_type': 'IntracellularElectrode', 'object_id': '506001d9-e4bd-43a8-ba59-9c935b392932'}, 'groups': {}, 'datasets': {'description': root/general/intracellular_ephys/elec0/description DatasetBuilder {'attributes': {}, 'data': 'a mock intracellular electrode'}}, 'links': {'device': root/general/intracellular_ephys/elec0/device LinkBuilder {'builder': root/general/devices/Heka ITC-1600 GroupBuilder {'attributes': {'namespace': 'core', 'neurodata_type': 'Device', 'object_id': '1e0bc3f0-ece5-4db9-8830-19387b89d320'}, 'groups': {}, 'datasets': {}, 'links': {}}}}}}}}, "Could not construct VoltageClampSeries object due to: VoltageClampSeries.__init__: missing argument 'gain'")
  File "/Users/smprince/Documents/code/hdmf/src/hdmf/build/objectmapper.py", line 1357, in construct
    obj = self.__new_container__(cls, builder.source, parent, builder.attributes.get(self.__spec.id_key()),
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smprince/Documents/code/hdmf/src/hdmf/build/objectmapper.py", line 1370, in __new_container__
    obj.__init__(**kwargs)
  File "/Users/smprince/Documents/code/hdmf/src/hdmf/utils.py", line 667, in func_call
    pargs = _check_args(args, kwargs)
            ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smprince/Documents/code/hdmf/src/hdmf/utils.py", line 660, in _check_args
    raise ExceptionType(msg)
TypeError: VoltageClampSeries.__init__: missing argument 'gain'
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

3.11

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?

### Additional contract requirements

- When `gain` is omitted from a `PatchClampSeries` constructor call, the resulting object's `gain` attribute must be `None`.
