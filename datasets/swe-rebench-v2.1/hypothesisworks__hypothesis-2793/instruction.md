Further distinguish errors by exception `__cause__` or `__context__`
We have [an internal notion of `interesting_origin`](https://github.com/HypothesisWorks/hypothesis/search?q=interesting_origin), which is used to distinguish multiple failures in a single test.  Currently, that's a tuple of `(type, filename, line_number)` for each exception... which doesn't help much when the code does a general `except Exception: raise SomeGenericError`.

I therefore propose that we should also distinguish the `interesting_origin` by [the `__cause__` or `__context__` of the error](https://docs.python.org/3/library/exceptions.html), to allow for finer-grained reporting - and more importantly finer-grained caching of distinct failing examples.

There's some more design work to do on exactly how to distinguish this; I'm inclined to think that "the same way that Python would report them" is sensible but could see an argument to e.g. save finer distinctions than we bother reporting.  We'll also probably want to distinguish between cause and context - `except ValueError as err: raise AssertionError from err` is different from `except ValueError: assert state_is_ok`.

Comments, examples where this would be useful (or not), or suggestions are welcome 😀
