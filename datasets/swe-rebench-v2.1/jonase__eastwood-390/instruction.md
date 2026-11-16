Support `clojure.test/is false`
`is false` is a useful and handy pattern for creating robust tests.

There's also `assert false`, but test suites aren't guaranteed to run under `*assert* true`.

Likewise there's `(throw ...)` but it's more verbose and arguably less intentful.
