testify `{assert|require}` packages seem to be missing `NotErrorAs` methods.
When using this gem of a library I realized that the `assert` and `require` package seem to be missing a convenience function for `NotErrorAs(...)`.

`{assert|require}.NotErrorIs(...)` does exist so the absence of the `error.As` equivalent feels weird.

If there is a reason for this, which I do not see, I would love to be enlightened, else I would happily create a PR for this (:

Right now one has to do the following steps to check for this (which kinda breaks the feel IMHO):

```Golang
var customErr *package.CustomErr
assert.Error(t, err)
assert.False(t, errors.As(err, &customErr))
```

or similar.
