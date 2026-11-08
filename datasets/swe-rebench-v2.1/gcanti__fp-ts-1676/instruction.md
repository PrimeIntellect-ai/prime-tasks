TaskEither.tryCatch should either try/catch or be renamed
## 🚀 Feature request

### Current Behavior

`TE.tryCatch` only handles promises which have been rejected.

### Desired Behavior

It should have the same semantics as a javascript `try`/`catch` construct.

Or it should be deprecated and renamed to something not misleading, such as `TE.catchRejectedPromise`

<!-- A clear and concise description of what you want to happen.  -->

### Suggested Solution

[HIDDEN]

### Who does this impact? Who is this for?

All users.

### Describe alternatives you've considered

Wrapping `TE.tryCatch` in a try/catch.

### Additional context

I did read the docs where it said that `r` cannot throw.

### Your environment

<!-- PLEASE FILL THIS OUT -->

| Software   | Version(s) |
| ---------- | ---------- |
| fp-ts      |   2.11.8         |
| TypeScript |   4.5.5         |

### Additional contract requirements

- `TaskEither.tryCatch` and `TaskEither.tryCatchK` must treat an exception thrown synchronously by `f` the same way as a rejected promise: the resulting task yields `Left` with the thrown value passed through `onRejected`, and does not reject.
- `TaskOption.tryCatch` and `TaskOption.tryCatchK` must yield `None` when `f` throws synchronously, the same as for a rejected promise.
