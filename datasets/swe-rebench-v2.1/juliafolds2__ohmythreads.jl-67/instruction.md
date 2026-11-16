Rename `@init` to `@tasklocal` or `@local`, make `@set init` set the `init` kwarg
I just realized that in `@tasks`, we

1) have no way to set the `init` keyword argument
2) the obvious way to do that would be with `@init` or `@set init = ...`, but that seems unnececarily confusing given that we also have `@init` for task local values.

Given that, I think it'd be good to do a renaming here before too many people start relying on `@tasks`. Any thoughts?

### Additional contract requirements

- The renamed macro is `@local` (exported from `OhMyThreads`), replacing `@init`. Inside a `@tasks for ... end` block it accepts either a typed assignment `name::T = value` or a `@local begin ... end` block containing one or more typed assignments, and makes the declared task-local values available as ordinary variables inside the loop body.
- `@set` accepts an `init` setting (for example `init=0.0`), including as an assignment inside a `@set begin ... end` block. When a reducer is supplied, `init` is used as the initial accumulator value of the reduction. When no reducer is supplied, `init` has no effect on the loop.
