run_sync does not clean up the pending task after run_until_complete is interrupted
When the wrapped method (like `BlockingKernelClient.get_shell_msg`) is interrupted by KeyboardInterrupt(Ctrl+C), the event loop is interrupted, and the task ( `asyncio.Task`  ) becomes a pending state.
If I call the wrapped method again, it does not return.

I think `run_sync` should cancel the pending task.
https://stackoverflow.com/questions/30765606/whats-the-correct-way-to-clean-up-after-an-interrupted-event-loop

### Additional contract requirements

- `run_sync` is a public function in the `jupyter_client.utils` module. It accepts a coroutine function and returns a callable that runs that coroutine to completion synchronously and returns its result.
- When the event loop is interrupted (for example by `KeyboardInterrupt`) or any `BaseException` is raised while awaiting, the pending `asyncio.Task` is cancelled before the exception is re-raised.
