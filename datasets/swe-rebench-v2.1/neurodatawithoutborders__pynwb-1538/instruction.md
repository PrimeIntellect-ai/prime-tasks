[Bug]: Timeseries can have timestamps + data that don't match in length
### What happened?

I use the convenient timeseries pointer feature, where you can just store timestamps in one timeseries and have many others point to them. This saves a lot of memory! However, I just fixed a bug that arose because some data I stored in a timeseries didn't have the same length as the timeseries (due to a processing mistake). Then I went and checked, and it turns out that timeseries' timestamps don't need to have the same length as the data at all! I consider this a bug, given that timeseries are meant as a core unit of data in NWB, but let me know if I'm just using them wrong.

### Steps to Reproduce

```python
# normal case
t = nwb.TimeSeries(name='test', data=np.arange(10), timestamps=np.arange(10), unit='sec')

# I expect a value error here
nwb.TimeSeries(name='test', data=np.arange(10), timestamps=np.arange(5), unit='sec')

# This similarly should raise an error imo
s = nwb.TimeSeries(name='test2', data=np.arange(2), timestamps=t, unit='sec')
```


### Traceback

```python
n/a
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

3.9

### Package Versions

nwb 2.0.0

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
