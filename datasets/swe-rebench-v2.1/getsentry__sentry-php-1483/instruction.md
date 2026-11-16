Do not call magic methods when seralizing object IDs in stack traces
This also invokes magic `__isset()` (and then `__get()` ) method for objects, which can be problematic if these magic methods have side effects. Which is exactly what I had to investigate and deal with in our own codebase today.

I'd propose that this behavior (magically getting some kind of ID of objects present within traceback) should check if the property _actually_ exists first [HIDDEN].

Or at least this magic feature should be optional - i,e. there should be an option to disable it.

_Originally posted by @smuuf in https://github.com/getsentry/sentry-php/pull/1443#discussion_r1116010136_

### Additional contract requirements

- When serializing an object in a stack trace, determining whether it has an ID must not invoke its magic methods, including `__isset()` or `__get()`.
