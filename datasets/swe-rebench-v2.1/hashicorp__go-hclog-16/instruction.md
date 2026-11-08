Change default time format
Is there any option to change default time format? I've found it's declared as a const now
```go
const TimeFormat = "2006-01-02T15:04:05.000Z0700"
```
It would be very helpful to have an option to pass format with `LoggerOptions`.

### Additional contract requirements

- Add a caller-configurable `TimeFormat string` option to `LoggerOptions`. When non-empty, it controls the timestamp format; otherwise, use the package default.
