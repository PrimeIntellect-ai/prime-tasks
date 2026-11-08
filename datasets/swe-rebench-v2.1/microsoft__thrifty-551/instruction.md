Const definitions referencing imported consts cannot be loaded
I have the following two thrift files:
___
`path/to/errors.thrift`
```thrift

const string ERROR_NOT_FOUND = "ErrorNotFound"
...
```
___
`service.thrift`
```thrift
include "path/to/errors.thrift"

const string NOT_FOUND = errors.ERROR_NOT_FOUND
...
```
___
While with Apache Thrift Compiler, I can generate code out of these two thrift files without issues, Thrifty failed to load `service.thrift` with the following error message:
```
E: Unrecognised const identifier: errors.ERROR_NOT_FOUND (at path/to/service.thrift)
```

Right now my workaround is to define `NOT_FOUDN` in `service.thrift` with literal `"ErrorNotFound"` instead of the imported reference `errors.ERROR_NOT_FOUND`.
