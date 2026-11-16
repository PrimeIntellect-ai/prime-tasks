Improve header row handling in multipart tabular resource chunks
# Overview

A multipart resource concatenates chunks as-is which is what we want for generic binary files.
But for tabular resource this default behaviour implies that if the first chunk does have one header row, the other chunks must not.
We discussed this issue here: https://github.com/frictionlessdata/forum/issues/1
The proposition is to change this behaviour for tabular-data-package:  tabular chunks should all have headers or none depending on dialect.header.

# Implementation

Multipart chunks are handled by the _MultipartSource class which build an iterator of chunks' rows iterator. [HIDDEN]
@roll pointed possible issues with:
- resource.raw_read: I've checked this method uses _MultipartSource iterator so should be safe
- datapackage.save: I am not sure to understand the risk in there since data are only read from resources. Saving only writes the datapackage not the data itself right ?

@pwalsh and @akariv your points of view and advices are more than welcome.

---

Please preserve this line to notify @roll (lead of this repository)

### Additional contract requirements

- For tabular multipart resources with headers enabled, the first chunk's header must remain, and header rows in subsequent chunks must not be exposed as data; their data rows must be preserved.
- When headers are disabled, rows from every chunk must be treated as data.
