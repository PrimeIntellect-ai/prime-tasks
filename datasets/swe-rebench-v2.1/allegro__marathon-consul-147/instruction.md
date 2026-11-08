Human-readable time durations in config files
It would be nice if we had human-readable time durations in config files instead of the nanosecond integers, for example:

``` json
"Sync": {
  "Interval": 900000000000
}
```

would become

``` json
"Sync": {
  "Interval": "15m"
}
```

### Additional contract requirements

- The package `github.com/allegro/marathon-consul/time` provides a public type `Interval` with an exported field `Duration` of type `time.Duration`.
- An `Interval` value is read from configuration JSON given as a human-readable duration string in the format accepted by `time.ParseDuration` (for example `"15m"`), and when serialized to JSON it is represented as such a human-readable duration string rather than a nanosecond integer.
- The `Timeout` field of `consul.Config` is of type `time.Interval`.
- The `Interval` field of `sync.Config` is of type `time.Interval`.
- The `Timeout` field of `marathon.Config` is of type `time.Interval`.
- The `Interval` field of `metrics.Config` is of type `time.Interval`.
