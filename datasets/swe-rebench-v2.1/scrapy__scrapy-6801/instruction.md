Add `SignalManager.send_catch_log_async()`
In addition to `SignalManager.send_catch_log_deferred()` which awaits on Deferreds returned from signal handlers (directly or by wrapping coroutines) we should have `SignalManager.send_catch_log_async()` which awaits on coroutines returned from signal handlers (directly or by wrapping Deferreds).

Related to #6705

### Additional contract requirements

- Add a public coroutine function `send_catch_log_async(signal, *args, **kwargs)` in module `scrapy.utils.signal`. It emits `signal` to all connected handlers, awaits any coroutine or Deferred returned by a handler, and resolves to a list of `(receiver, result)` tuples, where `result` is the handler's return value or a `twisted.python.failure.Failure` object if the handler raised an exception. Handler exceptions are logged. Positional and keyword arguments are passed unchanged to each handler.
- Add a public method `SignalManager.send_catch_log_async(signal, **kwargs)` on `scrapy.signalmanager.SignalManager` that behaves the same way.
