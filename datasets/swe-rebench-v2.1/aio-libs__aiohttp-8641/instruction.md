Risk of websocket ping tasks being garbage collected before they finish
              These are at risk of being garbage collected before they finish.

This is an existing problem to be solved in a future PR
https://docs.python.org/3/library/asyncio-task.html#asyncio.create_task
> Important [HIDDEN], to avoid a task disappearing mid-execution. The event loop only keeps weak references to tasks. A task that isn’t referenced elsewhere may get garbage collected at any time, even before it’s done. For reliable “fire-and-forget” background tasks, [HIDDEN]:

_Originally posted by @bdraco in https://github.com/aio-libs/aiohttp/pull/8608#discussion_r1704039542_

### Additional contract requirements

- A client-side or server-side WebSocket heartbeat ping task that has started must remain alive until it finishes, even if no other code retains a reference to it.
