Currying DSL functions
There are a lot of functions that will be useful and ergonomic if we translate them into currying functions.
The functions are:

- [x] `Raise.ensure`
- [x] `Raise.ensureNotNull`
- [x] `Raise.recover` (version with two parameters)
- [x] `Raise.catching`
- [x] `Raise.withError`

### Additional contract requirements

The following functions are public members of the object `in.rcard.raise4s.Raise`. Each takes its arguments in separate parameter lists (curried):

- `Raise.ensure[Error](condition: Boolean)(raise: => Error): Unit` — returns normally when `condition` is true; otherwise raises the supplied error. The error expression is evaluated only when `condition` is false.
- `Raise.ensureNotNull[B, Error](value: B)(raise: => Error): B` — returns `value` when it is not null; otherwise raises the supplied error. The error expression is evaluated only when `value` is null.
- `Raise.recover[Error, A](block: Raise[Error] ?=> A)(recover: Error => A): A` — returns the result of `block`, or the result of applying `recover` to a raised logical error. An exception thrown by `block` is rethrown and is not passed to `recover`.
- `Raise.catching[A](block: () => A)(catchBlock: Throwable => A): A` — returns the result of `block`; if a non-fatal exception is thrown, returns the result of applying `catchBlock` to it; fatal exceptions are rethrown.
- `Raise.withError[Error, OtherError, A](transform: OtherError => Error)(block: Raise[OtherError] ?=> A): A` — returns the result of `block`, or raises `transform` applied to a raised `OtherError` in the surrounding `Raise[Error]` context.
- An extension method `catching` on a by-name value `a: => A` in object `Raise`: `def catching(catchBlock: Throwable => A): A`, behaving like `Raise.catching`.
