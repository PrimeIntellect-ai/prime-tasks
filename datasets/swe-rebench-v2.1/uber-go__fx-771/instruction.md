[Question] Why `Invoked` events are logged as error by `ZapLogger`?
Hello, I am using the version `1.14.0` and I noticed that `Invoked` events are logged with error level by the `ZapLogger` even when the event does not carry an error.

https://github.com/uber-go/fx/blob/2f6e9690bc6e231a68c39ca88f8b6c90be62af86/fxevent/zap.go#L93-L101

Is there any specific reason for it or should it be at level Info in case of no error?

### Additional contract requirements

- `ZapLogger` (fxevent/zap.go) must log a successful `*Invoked` event (one whose `Err` is nil) at `Info` level, and a failed `*Invoked` event (non-nil `Err`) at `Error` level.
- `ConsoleLogger` (fxevent/console.go) must log a successful `*Invoked` event as a plain `fx.Invoke(<FunctionName>) called from:` line (no `ERROR` prefix), and a failed `*Invoked` event with an `ERROR` prefix that includes the error.
