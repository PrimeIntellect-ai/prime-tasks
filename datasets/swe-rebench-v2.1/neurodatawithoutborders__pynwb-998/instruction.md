Do not print empty containers in string representation of NWBFile
## 2) Feature Request

When printing an `NWBFile`, there are many fields that are not relevant to most users. This adds clutter. It can also be intimidating for users who are learning the format and regularly print objects to inspect them and debug.

I suggest not printing any empty containers. i.e. change the output of `print(nwbfile)` from:
```
root <class 'pynwb.file.NWBFile'>
Fields:
  acquisition: { RunningSpeed <class 'pynwb.base.TimeSeries'> }
  analysis: { }
  devices: { }
  electrode_groups: { }
  epoch_tags: {}
  ic_electrodes: { }
  imaging_planes: { }
  lab_meta_data: { }
  ogen_sites: { }
  processing_modules: { }
  stimulus: { }
  stimulus_template: { }
  time_intervals: { }
```
to
```
root <class 'pynwb.file.NWBFile'>
Fields:
  acquisition: { RunningSpeed <class 'pynwb.base.TimeSeries'> }
```

We already do not print empty / default attributes.


## Checklist

- [ ] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [ ] Have you included a brief and descriptive title?
- [ ] Have you included a clear description of the problem you are trying to solve?
- [ ] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [ ] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
