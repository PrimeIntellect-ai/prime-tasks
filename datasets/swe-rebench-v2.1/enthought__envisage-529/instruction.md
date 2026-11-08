Don't raise SystemError
Various parts of Envisage deliberately do a `raise SystemError`. `SystemError` is almost certainly the wrong exception type to be raising in any part of Envisage. From [the docs](https://docs.python.org/3/library/exceptions.html#SystemError):

> Raised when the interpreter finds an internal error, but the situation does not look so serious to cause it to abandon all hope. The associated value is a string indicating what went wrong (in low-level terms).

We should replace each use of `SystemError` with something more appropriate.
