Warning in docs about frozen classes no longer applicable
If you check the docs on frozen classes (https://www.attrs.org/en/stable/how-does-it-work.html#immutability), you'll note it says "You should avoid instantiating lots of frozen slotted classes [...] in performance-critical code."

However... with `attr.define`/`attr.frozen` both take the same amount of time.

```py
In [1]: import attr

In [2]: @attr.frozen
   ...: class SlottedFrozen:
   ...:     foo: int
   ...:     bar: int
   ...:     baz: str
   ...:     bing: float = 5.0
   ...:

In [3]: @attr.define
   ...: class SlottedUnfrozen:
   ...:     foo: int
   ...:     bar: int
   ...:     baz: str
   ...:     bing: float = 5.0
   ...:

In [4]: @attr.s(slots=True, frozen=True, auto_attribs=True)
   ...: class OldSlottedFrozen:
   ...:     foo: int
   ...:     bar: int
   ...:     baz: str
   ...:     bing: float = 5.0
   ...:

In [5]: @attr.s(slots=True, auto_attribs=True)
   ...: class OldSlottedUnfrozen:
   ...:     foo: int
   ...:     bar: int
   ...:     baz: str
   ...:     bing: float = 5.0
   ...:

In [6]: %timeit SlottedFrozen(7, 42, "hi!")
553 ns ± 10.6 ns per loop (mean ± std. dev. of 7 runs, 1000000 loops each)

In [7]: %timeit SlottedUnfrozen(7, 42, "hi!")
566 ns ± 17.2 ns per loop (mean ± std. dev. of 7 runs, 1000000 loops each)

In [8]: %timeit OldSlottedFrozen(7, 42, "hi!")
553 ns ± 8.64 ns per loop (mean ± std. dev. of 7 runs, 1000000 loops each)

In [9]: %timeit OldSlottedUnfrozen(7, 42, "hi!")
296 ns ± 3.09 ns per loop (mean ± std. dev. of 7 runs, 1000000 loops each)
```

What's up? Well, turns out the new API is setting `on_setattr=attr.setters.validate`. This turns the `__init__` from this: (old)
```py
In [14]: print(inspect.getsource(OldSlottedUnfrozen.__init__))
def __init__(self, foo, bar, baz, bing=attr_dict['bing'].default):
    self.foo = foo
    self.bar = bar
    self.baz = baz
    self.bing = bing
```

To this: (new)
```py
In [15]: print(inspect.getsource(SlottedUnfrozen.__init__))
[HIDDEN]
```

Possible solutions:
 - Mark that the note no longer applies
 - [HIDDEN]

### Additional contract requirements

- The fast path applies whenever the class-level `on_setattr` is
  `attr.setters.validate` and no field (including fields inherited from base
  classes) defines a validator. This includes classes built with the classic
  `attr.s` API that pass `on_setattr=attr.setters.validate` explicitly. In
  that case the class's `__setattr__` remains `object.__setattr__`.
