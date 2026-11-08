False positive in C416
Example file, `demo.py`
```python
import asyncio


async def ticker(delay, to):
    for i in range(to):
        yield i
        await asyncio.sleep(delay)


async def main():
    return [item async for item in ticker(1, 10)]

```

Error message,
```
demo.py:5:15: C416 Unnecessary list comprehension - rewrite using list()
```

I don't think we can rewrite asynchronous list/dict/set comprehensions (https://www.python.org/dev/peps/pep-0525/#asynchronous-list-dict-set-comprehensions) using `list()`, `dict()` or `set()`.
