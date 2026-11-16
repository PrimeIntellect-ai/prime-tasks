Consider adding support for special numbers in almosteq()
I.e. ``nan`` is not considered close to any other value, including ``nan`. ``inf`` and ``-inf`` are only considered close to themselves.  See also [PEP 485](https://peps.python.org/pep-0485/).

If that will be accepted, we also could use ``math.isclose()`` to implement ``almosteq()`` for the fp backend.  Probably this should be slightly faster.

Right now we have:
```pycon
>>> from mpmath import inf, mp
>>> mp.almosteq(inf, inf)
False
```
c.f.
```pycon
>>> from math import inf, isclose
>>> isclose(inf, inf)
True
```

Are there good reasons why ``almosteq()`` behave differently from the ``math.isclose()``?
