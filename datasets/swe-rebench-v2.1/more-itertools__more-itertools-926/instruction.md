Sync with itertools recipes:  loops()
Recently a new `loops()` recipe was added to the [CPython main docs](https://docs.python.org/3/library/itertools.html#itertools-recipes).

```
def loops(n):
    "Loop n times. Like range(n) but without creating integers."
    # for _ in loops(100): ...
    [HIDDEN]
```

Simple test:

```
>>> all(list(loops(n)) == [None] * n for n in range(-10, 10))
True
```

It is intended to be used like this:

```
>>> for _ in loops(5):
...     print('hello world')
...
hello world
hello world
hello world
hello world
hello world
```

### Additional contract requirements

Add a public function `loops(n: int) -> Iterator[None]` in the `more_itertools` package, exposed as `more_itertools.loops`. The returned object is an iterator that yields the value `None` exactly `n` times; when `n` is zero or negative the iterator is empty.
