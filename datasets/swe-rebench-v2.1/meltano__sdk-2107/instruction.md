feat: Make `Stream.get_starting_*()` methods return `None` for full-table replication streams
### Feature scope

Taps (catalog, state, stream maps, tests, etc.)

### Description

If a user leverages the Singer catalog to change the default replication method of a stream from _incremental_ to _full-table_, the hard-coded calls to `get_starting_*()` remain, and a bookmark is retrieved if it's available in the state and may cause results to be filtered, which goes against the intent of forcing full-table replication.

## Workarounds

Users can manually edit the state to remove the bookmark of the stream in question.

## Refs

- [`singer_sdk.Stream.get_starting_timestamp`]( https://sdk.meltano.com/en/v0.33.1/classes/singer_sdk.Stream.html#singer_sdk.Stream.get_starting_timestamp)
- [`singer_sdk.Stream.get_starting_replication_key_value `]( https://sdk.meltano.com/en/v0.33.1/classes/singer_sdk.Stream.html#singer_sdk.Stream.get_starting_replication_key_value)
- [Slack](https://meltano.slack.com/archives/C01TCRBBJD7/p1700682527418919)
