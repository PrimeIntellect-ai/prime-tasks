NWBFile does not represent units or epochs in repr or str
### Issue
The `__repr__` or `__str__` for NWBFile do not display information about epochs or units. They are displayed as `None` even if they have content.

### Use Case
We want to be able to inspect the contents of an NWB file.

### Minimal example
Here is an example for epochs; units behaves similarly.
Create a basic NWBFile with an epoch:
```python
dataset_zero_time = datetime(2006, 1, 2, 12, 0, 0, tzinfo=tz.gettz('US/Pacific'))
file_create_date = datetime.now(tz.tzlocal())
data_dir = 'path/to/nwb/files'
nwb_filename = 'test.nwb'
nwbf = pynwb.NWBFile(session_description='no session description',
                     identifier='no identifier',
                     session_start_time=dataset_zero_time)
nwbf.add_epoch(start_time=1.0,
               stop_time=10.0,
               tags=['tag1', 'tag2'])

print(nwbf)
```

Results:
```python
root <class 'pynwb.file.NWBFile'>
Fields:
  ...
  ...
  epoch_tags: {'tag2', 'tag1'}
  epochs: None
  ...
  ...
```

After round-tripping the data, we don't see epochs_tags either.
```
with pynwb.NWBHDF5IO(nwb_filename, mode='w') as iow:
    iow.write(nwbf)

io = pynwb.NWBHDF5IO(nwb_filename, mode='r')
nwbf_read = io.read()

print(nwbf_read)
```

Results:
```
root <class 'pynwb.file.NWBFile'>
Fields:
  ...
  ...
  epoch_tags: set()
  epochs: None
  ...
  ...
```

### Environment
- Python 3.6.7
- MacOS 10.14
- Pynwb 1.0.0 dev (pip)

## Checklist
- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?

### Additional contract requirements

- When `tags=['tag1', 'tag2']`, the printed fields must include `epoch_tags: {'tag1', 'tag2'}` and `epochs: epochs <class 'pynwb.epoch.TimeIntervals'>`.
- `NWBFile.add_epoch(start_time, stop_time, tags=None)` stores the supplied `start_time` and `stop_time` as an interval in the `epochs` table. The `tags` argument is optional.
- After writing an NWBFile that contains an epoch to a file and reading it back, the printed fields must include `epochs: epochs <class 'pynwb.epoch.TimeIntervals'>`.
