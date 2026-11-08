Sendable Case Paths?
I've been getting some warnings when I capture a 'non-sendable' case path in a `@Sendable` closure.

It there any reason `CasePath` can't be marked `Sendable` where the `Root` is already `Sendable`? I _think_ this will be okay, but would like to make sure

🤔

### Additional contract requirements

A `CasePath` whose `Root` conforms to `Sendable` must itself be usable as a `Sendable` value, including when captured by an `@Sendable` closure. Concurrent calls to a shared `CasePath`'s `embed` and `extract` operations must safely invoke their stored closures.
