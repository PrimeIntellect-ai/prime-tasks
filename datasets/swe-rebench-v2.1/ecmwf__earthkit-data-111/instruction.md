to_pandas fails for bufr when no filters argument specified
### What happened?

Running this code:

```
ds = earthkit.data.from_source("file", "synop.bufr")
r = ds.to_pandas(columns=["latitude", "longitude"])
```
results in the following error:
```
File "git/pdbufr/pdbufr/bufr_structure.py", line 616, in stream_bufr
    filters = dict(filters)
TypeError: 'NoneType' object is not iterable
```

To make it work `filters` must be specified. E.g.:

`r = ds.to_pandas(columns=["latitude", "longitude"], filters={})`

### What are the steps to reproduce the bug?

See above

### Version

0.1.3, develop

### Platform (OS and architecture)

all

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

_No response_
