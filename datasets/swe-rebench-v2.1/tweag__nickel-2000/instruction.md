Short-circuiting version of `fold_left`
**Is your feature request related to a problem? Please describe.**

`fold_left` is a useful combinator, and the one most often used for general iteration in functional programming (preferred over `fold_right`). However, as opposed to `fold_right`, it's not short-circuiting. For example, here is an excerpt of the implementation of `std.contract.Sequence`:

```nickel
std.array.fold_left
  (
    fun acc Contract =>
      acc
      |> match {
        'Ok value =>
          std.contract.apply_as_custom Contract label value,
        # if we encountered an error at some point in the pipeline, we
        # just forward it from this point
        error => error
      }
  )
  ('Ok value)
  contracts
```

The idea is that we want apply the contracts from the given `contracts` list as long as they don't return an error, but stop at the first error. But we have to manually match on the accumulator and propagate the short-circuiting case all-along (`error => error`), which is a bit clumsy. This isn't the only place where this takes place.

**Describe the solution you'd like**

Add a function in the stdlib that would have a signature like:

```nickel
try_fold_left: forall a b c. (a  -> c -> Result a b) -> a -> Array c -> Result a b
```

Where `Result a b := [| 'Ok a, 'Error b |]` (or something different, like `Some/None`, `Continue/Stop`, etc.). Whether it would be just sugar for the previous example, or it would use a special primop to actually be short-circuiting is an important question but even just a helper function to avoid the propagate-the-error boilerplate would be useful.

### Additional contract requirements

Provide the standard-library array combinator `std.array.try_fold_left`. Its callback returns either `'Ok` with an updated accumulator to continue or `'Error` with a value to stop and return. For an array whose callback continues throughout, process elements from left to right, thread each updated accumulator into the next call, and return the final accumulator in `'Ok`. On the first `'Error`, return that error and do not invoke the callback for later elements.
