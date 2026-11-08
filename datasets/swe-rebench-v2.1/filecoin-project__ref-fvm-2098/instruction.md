Move the actor logs into the trace
At the moment, when actor debugging is enabled logs are written to [stdout](https://github.com/filecoin-project/ref-fvm/blob/ed6d34abae49257f15f226699e36dd51e00f2e4d/fvm/src/kernel/default.rs#L955). Instead, we should record them in the execution trace inside of the call manager. I.e., each log becomes an `ExecutionEvent`:

https://github.com/filecoin-project/ref-fvm/blob/ed6d34abae49257f15f226699e36dd51e00f2e4d/fvm/src/trace/mod.rs#L21-L40

If we do this, it should become _much_ easier to debug actors from clients. Instead of having to:

1. Restart the client with some env var enabled.
2. Read stdout/stderr.

We can invoke the FVM with debug tracing enabled and return the serialized logs over RPC.

### Additional contract requirements

- Every actor log message emitted while debugging is enabled must be recorded in the execution trace of the call (the `exec_trace` reported in the call's finish result), as an entry that contains the message text.
- The `CallManager` trait must provide a `log(&mut self, msg: String)` method that records the message in the execution trace. Every `CallManager` implementation provides it.
- Actor log messages must not be written to standard output.
