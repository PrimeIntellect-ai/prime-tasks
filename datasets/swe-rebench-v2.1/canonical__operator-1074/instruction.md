Layer object support for log-forwarding as a field
`log-targets` has been added as a field to pebble as of https://github.com/canonical/pebble/pull/267. However, the current implementation of ops.pebble.Layer discards this from the argument of the init. This must be handled properly so that the layer yaml file could be produced.
