Enabled + stack unwinding
RuntimeInfo.CallDepth is documented as:

```
	// CallDepth is the number of call frames the logr library adds between the
	// end-user and the LogSink.  LogSink implementations which choose to print
	// the original logging site (e.g. file & line) should climb this many
	// additional frames to find it.
```

It's 1, which is correct for the `LogSink.Info` and `LogSink.Error` calls, e.g.
https://github.com/go-logr/logr/blob/eea184c40063709bc85c75834aa3305555441171/logr.go#L278

But it is not correct for the `LogSink.Enabled` call in `Logger.Info`:
https://github.com/go-logr/logr/blob/eea184c40063709bc85c75834aa3305555441171/logr.go#L274

There the call chain is `[HIDDEN]`.

It is correct again for `<user code> -> Logger.Enabled -> LogSink.Enabled`.

### Additional contract requirements

- When `Logger.Info` checks whether logging is enabled, `RuntimeInfo.CallDepth` must allow the sink to identify the original user call site, consistent with its documented meaning.
- The actual `LogSink.Info` call must also retain the documented call depth so the sink can identify the original logging site.
