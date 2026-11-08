[Feature]: Support de-selecting a stream by default
### Feature scope

Taps (catalog, state, stream maps, etc.)

### Description

Tap developers may want to disable certain streams in their taps for a few reasons:

- The stream requires higher access credentials than the rest
- The stream requires a different payment tier in the source system
- The stream has a large volume of data and not all users may be interested in it by default

The discovered catalog would flag the stream with `"selected_by_default": false`. This means that with no catalog file, the stream selection will be resolved to `False`.

End users could still toggle the stream selection as normal by passing a catalog file.

Related discussion:

- https://github.com/meltano/sdk/discussions/1652

### Additional contract requirements

A tap developer can set `selected_by_default = False` on an individual stream class to make that stream unselected when no input catalog is supplied. The discovered catalog includes the stream-level `selected_by_default` metadata flag set to false for that stream. An input catalog can still select the stream.
