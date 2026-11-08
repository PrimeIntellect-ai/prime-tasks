Version 1 cfilter and cfilterheader are deprecated
Since the version 1 cfilters are deprecated and will be removed in v1.7.0, the JSON-API docs, RPC server help, and relevant code needs to be updated to call out they are deprecated and should not be used.  Use version 2 cfilters instead.

### Additional contract requirements

The JSON API documentation entries for `getcfilter` and `getcfilterheader`, and the RPC help shown for those commands, must identify the commands as deprecated and direct users to `getcfilterv2`. Go documentation for the legacy filter and filter-header methods on `blockchain/indexers.CFIndex` must identify those APIs as deprecated and direct users to their version 2 filter API.
