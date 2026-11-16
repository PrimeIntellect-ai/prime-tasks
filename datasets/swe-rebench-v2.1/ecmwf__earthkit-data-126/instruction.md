GRIB or BUFR files are recognised as unknown type
### What happened?

It happens when a GRIB or BUFR file does not start with the "GRIB" or "BUFR" bytes, but they contain some padding or data transmission headers. Then `from_source` assigns the `unknown` type to them.

### What are the steps to reproduce the bug?

Use

```
 wget https://github.com/ecmwf/pdbufr/raw/master/tests/sample-data/M02-HIRS-HIRxxx1B-NA-1.0-20181122114854.000000000Z-20181122132602-1304602.bufr --output-document=hirs.bufr
```
then

```python
import earthkit.data
ds  = earthkit.data.from_source("file", "hirs.bufr")
```


### Version

any

### Platform (OS and architecture)

any

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

_No response_

### Additional contract requirements

- The public `earthkit.data.settings` object provides `get(name)` and `set(name, value)`. Unknown setting names raise `KeyError`; a value of the wrong type raises `TypeError`; a value rejected by validation raises `ValueError`.
- The `reader-type-check-bytes` setting controls how many leading source bytes are inspected to identify a reader type. Its default is 64. It accepts integer values from 8 through 4096 inclusive; integers outside that range are rejected with `ValueError`.
