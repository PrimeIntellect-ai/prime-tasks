Consider removing `occurred: Instant` lambda parameters from `Pulse.beat` and `Clock.executeAt`
These values might be misleading if someone is blocking the event loop. Blocking the event loop is obviously bad, but we won't want people using these `occurred` values in their health checks if they're possibly not accurate. Plus, they provide very little value to the end user since they can just do this instead.

```kt
clock.fixedPeriodPulse(10.seconds) { scheduled ->
  val occurred = clock.now()
  ...
}

clock.executeAt(...) {
  val occurred = clock.now()
  ...
}
```

This would also allow us to remove the parameter-less `Pulse.beat` function since you can implicitly omit a single lambda parameter versus needing to do `_, _ ->` everywhere.

### Additional contract requirements

- `Pulse.beat` must expose exactly one overload: `beat(strategy: PulseBackpressureStrategy = PulseBackpressureStrategy.ExecuteConcurrently, action: suspend (scheduled: Instant) -> Unit)`. The obsolete overload that accepted an `occurred` instant and the parameterless overload must not be present.
