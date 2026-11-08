Settings.throwOnInvalid = true breaks Interval.fromISO for <start>/<duration> ISO input
When ```Settings.throwOnInvalid = true``` is set the following code in Interval.js static fromISO
```js
[HIDDEN]
```

throws which means that the subsequent handling of duration ISO is never reached.

Reproduction:
```js
Settings.throwOnInvalid = true
const interval = Interval.fromISO('2020-06-22T17:30:00.000+02:00/PT5H30M')
```
Throws:
```
InvalidDateTimeError: Invalid DateTime: unparsable: the input "PT5H30M" can't be parsed as ISO 8601
```

### Additional contract requirements

- With `Settings.throwOnInvalid = true`, `Interval.fromISO` must successfully parse valid ISO intervals in both `start/duration` and `duration/start` forms without throwing; the returned interval must have `isValid` set to `true`.
