Calling watch.stop() does not close the response correctly
https://github.com/tomplus/kubernetes_asyncio/blob/d57e9e9be11f6789e1ce8d5b161acb64d29acf35/kubernetes_asyncio/watch/watch.py#L123-L124

It just raises an exception to exit.

I think we should add async context manager support for `Watch` objects, so it closes the response in `__aexit__`.

### Additional contract requirements

- `Watch` (in `kubernetes_asyncio.watch`) supports the asynchronous context manager protocol. Entering `async with watch as w:` yields the same `Watch` instance (`w is watch`), and leaving the block closes the response.
- `Watch.close()` releases the stored HTTP response by calling its `release()` method when a response is present, and clears the stored reference so the same response is not released again.
- `Watch.stream(func, *args, **kwargs)` returns an asynchronous iterator that also supports `async with watch.stream(...) as stream:`. Leaving that block closes the response. The call to `func` is made with `watch=True` and `_preload_content=False`.
