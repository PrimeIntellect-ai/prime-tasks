[Feature]: Automatic catalog inclusion of replication keys
### Feature scope

Taps (catalog, state, stream maps, etc.)

### Description

The standard metadata generated for streams with known schemas marks primary keys with `automatic` selection:

https://github.com/meltano/sdk/blob/eab95fca545c55b06f48e3264271197d12b812af/singer_sdk/_singerlib/catalog.py#L194-L200

We should probably do the same about replication keys.
