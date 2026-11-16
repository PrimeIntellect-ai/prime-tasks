maybe exclude event.events.k8s.io by default?
I can hardly think anyone would actually want to get all events (and similar status objects). The output is much more useful when I run `get-all | grep -v ^event`.

Maybe exclude `events/*` and `event.events.k8s.io/*` by default and offer an `--include-events` flag?

### Additional contract requirements

- The default exclusion list is `["events"]`, so that event resources are excluded by default.
- The CLI exposes a flag `--exclude` whose default value is `events`.
- Users can include events by clearing the default exclusion with `--exclude=`.
