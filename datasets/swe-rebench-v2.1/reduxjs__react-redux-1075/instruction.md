`isPlainObject()` util returns `false` for objects without prototypes
`Object.create(null)` produces a plain object whose prototype is `null`. Lodash's `isPlainObject()` correctly treats this as a plain object, but the `isPlainObject()` helper introduced in #936 does not. This broke our app, since we have a number of selectors which return prototypeless objects.

PR to follow.
