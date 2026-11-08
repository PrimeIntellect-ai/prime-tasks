Pong's CancelledError races with ConnectionClosed error
I upgraded to the current version of this library and I find it difficult to handle `asyncio.CancelledError` in case the pong is being cancelled due to a disconnect.

What happens in my server is that I'm waiting for pongs in one task while sending and receiving in another task. Both tasks are being waited for. The result is that in some occasions, `asyncio.CancelledError` is raised before `websockets.ConnectionClosed` and vice versa. When the `asyncio.CancelledError` is raised first, there is no context on why it has been raised.

Another problem with `asyncio.CancelledError` is that there's no way (IIRC) of finding out whether the current task has been cancelled or the task I'm waiting for has been cancelled. But this mainly is an awkward concept of asyncio and not this libraries fault. It seems one has to be extremely careful on when to cancel a task and when not to cancel a task and instead use other ways to signal cancellation (which highly depends on the task). This may clash with the design choice of this library.

TL;DR: I would prefer it if this library would raise `websockets.ConnectionClosed` in the pong's future instead of cancelling the pong.

### Additional contract requirements

When the connection closes, every ping future still waiting for a pong must complete with a `ConnectionClosed` exception rather than being cancelled.
