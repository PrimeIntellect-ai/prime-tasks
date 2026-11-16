ImagingPlane device argument should be link to device, not str
https://github.com/NeurodataWithoutBorders/pynwb/blob/ddeaacc464e567f3fc123ca74a6d8cecbfbbce15/src/pynwb/ophys.py#L59

Correct me if I'm wrong, but I think for consistency with ephys, the device argument of ImagingPlane should expect a Device type, not a str.

### Additional contract requirements

- `IntracellularElectrode` (in `pynwb.icephys`) must accept a `pynwb.device.Device` instance for its `device` argument and expose it as the electrode's `device`; passing a value that is not a `Device` must raise a `TypeError`.
- `ImagingPlane` (in `pynwb.ophys`) must accept a `pynwb.device.Device` instance for its `device` argument and expose it as the imaging plane's `device`; passing a value that is not a `Device` must raise a `TypeError`.
- `NWBFile.add_device` (in `pynwb.file`) must accept a `pynwb.device.Device` instance and add it to the file's devices; passing a value that is not a `Device` must raise an error.
