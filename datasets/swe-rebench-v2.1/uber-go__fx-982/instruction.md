Allow setting level of Zap Logger used for logging
The Zap logger that gets passed to fx via `WithLogger` gets logs at `Info` level for all messages except when things error out, which are logged at `Error` level.

We can consider exposing a way to set the level of these logs.

### Additional contract requirements

`*fxevent.ZapLogger` provides `UseLogLevel(level zapcore.Level)` to configure non-error Fx event logs and `UseErrorLevel(level zapcore.Level)` to configure error-related Fx event logs independently; `zapcore.Level` is from `go.uber.org/zap/zapcore`. With neither setting changed, non-error events are logged at Info and error-related events at Error.
