Custom MongoDB Collection name for `events`
**Is your feature request related to a problem? Please describe.**
Currently the eventstore forces you to use `events` as your MongoDB collection name. Possibility to specify this by developer would make a lot.

**Describe the solution you'd like**
Add option to configure the value. I am unable to provide enough good solution to this, so leaving feature request here.

**Additional context**

https://github.com/looplab/eventhorizon/blob/main/eventstore/mongodb_v2/eventstore.go#L69-L70

https://github.com/looplab/eventhorizon/blob/main/eventstore/mongodb/eventstore.go#L65-L68

### Additional contract requirements

- In the `eventstore/mongodb` package, add a public option `WithCollectionName(eventsColl string) Option` that configures the event store to use `eventsColl` for events instead of the default `events`. Without this option, events continue to use `events`. Applying the option with an empty name must fail with an error containing `missing collection name`.
- In the `eventstore/mongodb_v2` package, add a public option `WithCollectionNames(eventsColl string, streamsColl string) Option` that configures the event store to use `eventsColl` for events and `streamsColl` for streams instead of the defaults `events` and `streams`. Without this option, events and streams continue to use those defaults. Applying the option with two equal, non-empty names must fail with an error containing `custom collection names are equal`. If exactly one name is empty, it must fail with an error containing `missing collection name`; if both names are empty, it must fail with an error containing `custom collection names are equal`.
