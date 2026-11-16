Redis monitoring always setting the version to 0
## Is your feature request related to a problem? Please describe

When monitoring a Redis key, the version is always set to `0`. See [here](https://github.com/beatlabs/harvester/blob/master/monitor/redis/watcher.go#L80):

```go
// file: /monitor/redis/watcher.go#L80

changes = append(changes, change.New(config.SourceRedis, key, values[i].(string), 0))
```

Then, when the field's value is set, it will always trigger a debug log and send a change notification, see [here](https://github.com/beatlabs/harvester/blob/master/config/config.go#L102-L123):

```go
// file: /config/config.go#L102-L123

func (f *Field) Set(value string, version uint64) error {
	if version != 0 && version < f.version { // <--- version is 0, so it will not match
		log.Errorf("version %d is older than the field's %q (version %d)", version, f.name, f.version)
		return nil
	}

	if version != 0 && version == f.version { // <--- version is 0, so it will not match
		log.Debugf("version %d is the same as field's %q", version, f.name)
		return nil
	}

	prevValue := f.structField.String()

	if err := f.structField.SetString(value); err != nil {
		return err
	}

	f.version = version
	log.Debugf("field %q updated with value %q, version: %d", f.name, f, version) // <--- this one will always evaluate
	f.sendNotification(prevValue, value) // <--- this one as well
	return nil
}
```

2 issues:
1. There will be one log for each Redis key and at each monitoring tick, even though the value didn't change
2. It sends a notification to `chNotifications` for no reason

## Is this a bug? Please provide steps to reproduce, a failing test etc.

Yes.

To reproduce, monitor a Redis key, enable debug logs and tail the logs.

## Describe the solution

We need to increment the Redis version if there is a change.

Proposed solution:
[HIDDEN]

### Additional contract requirements

- Maintain an independent version for each monitored Redis key. The first observed value for a key has version 1; increment that key’s version by one for each subsequent value change. Unchanged values do not advance the version or produce a change notification.
- Repeated observations of an unchanged Redis value must not produce the redundant per-tick debug log described above.
