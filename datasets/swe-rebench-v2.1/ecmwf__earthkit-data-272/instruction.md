Test test_grib_output_pl fails
### What happened?

This test fails with

 `gribapi.errors.ReadOnlyError: Value is read only`

when trying to set `levtype=pl` on a GRIB message. This happens because since ecCodes 2.33.0 `levtype` is a readonly key.

### What are the steps to reproduce the bug?

See above

### Version

ecCodes >= 2.33.0

### Platform (OS and architecture)

all

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

ECMWF
