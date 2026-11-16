Make "logger.catch()" compatible with asynchronous generators
Eg in:

```python
import asyncio
from loguru import logger


@logger.catch
async def foo():
    yield 1
    yield 2
    raise ValueError


async def main():
    async for i in foo():
        print(i)

    print("Done")


asyncio.run(main())
```

### Additional contract requirements

- Decorating an asynchronous generator function with `@logger.catch` returns an asynchronous generator that can be consumed with `async for`. Values yielded before an exception is raised are delivered to the consumer.
- An exception escaping the decorated asynchronous generator is logged the same way `logger.catch` logs any other caught exception (at its level, with its traceback).
- With the default `reraise=False`, the exception is not propagated: asynchronous iteration ends and the code following the loop runs.
- With `reraise=True`, the exception is logged and then propagated to the consumer.
- `asend()` and `athrow()` on the decorated generator keep the usual asynchronous-generator behaviour: a value passed to `asend()` is received by the generator's `yield` expression, `athrow()` returns the next value yielded by the generator when the generator handles the thrown exception, `athrow()` propagates an exception the generator does not handle, and `StopAsyncIteration` is raised once the generator has finished.
