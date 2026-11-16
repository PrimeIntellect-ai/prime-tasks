Allow the ability to define the initial timestamp for the packetizer.
## Summary

Currently the timestamp is defined using a random number

https://github.com/pion/rtp/blob/319e780b743768216fcd1facedd8b26ca208ff01/packetizer.go#L40

This doesn't allow for syncing tracks from multiple sources where we can then swap the tracks from the server without repair.

## Motivation

I have 4 video sources with different quality settings but they cannot be used with ABR since the initial timestamps do not correspond with each other.

### Additional contract requirements

Callers must be able to set the initial RTP timestamp when constructing a packetizer. Provide this capability through `NewPacketizerWithOptions` and a `WithTimestamp` option; the configured value must appear as the timestamp on packets emitted before timestamp advancement.
