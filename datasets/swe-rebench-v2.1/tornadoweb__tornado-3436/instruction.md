run_sync raises TimeoutError on explicit event-loop stop
When a coroutine passed to `run_sync` doesn't finish because the event loop is stopped explicitly, the error raised is a somewhat confusing:

> TimeoutError: Operation timed out after None seconds


Repro:

```python
import asyncio
from tornado.ioloop import IOLoop

async def main():
    await asyncio.sleep(1)
    # ask the loop to stop
    IOLoop.current().stop()
    # coroutine doesn't finish
    await asyncio.sleep(10)

if __name__ == "__main__":
    IOLoop.current().run_sync(main)
```

I'm not even sure it needs to not be a TimeoutError, but the message should probably at least distinguish between the timeout having triggered and the loop stopping for other reasons. Right now, [this bit](https://github.com/tornadoweb/tornado/blob/385fd8823db043b787f2ca38c46628739deff6b4/tornado/ioloop.py#L534-L535) assumes a timeout is the only way the loop might stop before the given coroutine exits.
