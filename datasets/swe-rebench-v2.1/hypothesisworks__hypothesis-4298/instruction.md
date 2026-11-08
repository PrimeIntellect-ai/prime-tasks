Random `.random()` gives 1.0
`hypothesis.strategies.randoms()` provides an instance of `ArtificialRandom`.

It's  `.random()` method is equivalent to `hypothesis.strategies.floats(0, 1)` that has the domain of [0.0, 1.0] (inclusive).

> https://github.com/HypothesisWorks/hypothesis/blob/hypothesis-python-6.128.3/hypothesis-python/src/hypothesis/strategies/_internal/random.py#L237
> https://github.com/HypothesisWorks/hypothesis/blob/hypothesis-python-6.128.3/hypothesis-python/src/hypothesis/strategies/_internal/random.py#L174

However, it is deviated from well-known implementation of RNG that is half-open, e.g., `random.Random` of CPython
> Return the next random floating-point number in the range 0.0 <= X < 1.0
> https://docs.python.org/3/library/random.html#random.random

Some programs rely on this characteristic to work properly.

Is this behavior intended? How to exclude it from generating effectively?
