make NetcdfHandler conform to the DMRParser data model
The `NetcdfHandler` is broadly used for testing, and so it has not received a lot of development/update. This is true compared to the dataset that results from the downloading DAP responses (via dmr parser).
The differences lie in the attributes of the resulting dataset.

## Minimal Example

Consider [this remote dataset](http://test.opendap.org/opendap/dap4/SimpleGroup.nc4.h5.dmr.html)

```python
pyds.tree()
.SimpleGroup.nc4.h5
├──SimpleGroup
│  ├──Y
│  ├──X
│  ├──Temperature
│  └──Salinity
├──time
├──Z
├──Pressure
└──time_bnds
```
### DMR parser dataset
In particular the following are consistent with the desired DAP4 behavior:
```python
pyds.attributes
>>> {'description': 'A simple group for testing.'"
```
```python
pyds.dimensions
>>> {'time': 1, 'nv': 2, 'Z': 1000}
```
```python
ds['SimpleGroup/Temperature'].dims
>>> ['/time', 'Y', 'X']
```

### NetcdfHandler
Meanwhile
```python
pyds = NetCDFHandler('SimpleGroup.nc4').dataset
pyds.attributes
>>> {'NC_GLOBAL': {'description': 'A simple group for testing.'},
 'dimensions': OrderedDict([('time', 1), ('nv', 2), ('Z', 1000)])}
```
```python
pyds.dimensions
>>> OrderedDict([('time', 1), ('nv', 2), ('Z', 1000)])
```
```python
pyds['SimpleGroup/Temperature'].dimensions
>>> ('/time', '/SimpleGroup/Y', '/SimpleGroup/X')
```
but `pyds['SimpleGroup/Temperature'].dims` yields a KeyError.

### Summarizing
The following are the three changes that need to be implemented.

1. `pyds.attributes` Should be flat (no `NC_Global` container)
2. `pyds[key].dimensions` where `key` is a `Group` should return a dictionary.
3. `pyds[key].dims` where `key` is a BaseType (an array) should return a list and not a tuple.


This should allow for better/easier testing in pydap and xarray.
