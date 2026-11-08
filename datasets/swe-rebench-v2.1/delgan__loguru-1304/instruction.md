Make `.catch()` context manager async compatible
Hi,

First, thanks for a lot for loguru :)

I have a piece of code like this:

```python
import httpx
from loguru import logger as loguru_logger

@app.get("/")  # some fastapi route
async def my_route(foo, bar):
    logger = loguru_logger.bind(foo=foo, bar=bar)  # add some context to my logger
    with logger.catch():  # first context manager
        async with httpx.AsyncClient() as client:  # second context manager
            r = await client.get('https://www.example.com/')
            # do stuff...
```

In python, it's possible to chain context managers:
```python
with A() as X, B() as Y, C() as Z:
    do_something()
```

But I don't think it's possible to mix async and sync context managers.

So I wonder if we could make the class `Catcher` async compatible? I think that it would require implementing [HIDDEN]

This feature would allow this:

```python
import httpx
from loguru import logger as loguru_logger

@app.get("/")  # some fastapi route
async def my_route(foo, bar):
    logger = loguru_logger.bind(foo=foo, bar=bar)  # add some context to my logger
    async with logger.catch(), httpx.AsyncClient() as client:  # all in one line
        r = await client.get('https://www.example.com/')
        # do stuff...
```

Thanks
