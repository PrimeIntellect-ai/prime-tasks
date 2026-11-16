context-as-argument is unsatisfiable sometimes
**Describe the bug**

The [context-as-argument](https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md#context-as-argument) linter is unsatisfiable if a function accepts more than one context as parameters to the function.

**To Reproduce**

It is impossible to satisfy the linter with code like this (I haven't specifically tested this exact code block, but there's no way it _shouldn't_ trigger the linter...)

```go
func foo(ctx context.Context, other context.Context) {
    ...
}
```

```context-as-argument: context.Context should be the first parameter of a function```

**Expected behavior**

I would expect it to recognize that the first argument _is_ `ctx context.Context` and be satisfied. Beyond that, it would probably be okay if it checked that all the `context.Context` parameters are grouped at the beginning of the argument list, but that is a stylistic choice that I don't have a strong opinion on here.

**Additional context**

Sometimes it is useful to implement functionality like waiting on the expiration of either of two contexts. At the moment, I have to explicitly ignore this linter in those rare situations, simply because there is no way to make the linter happy here.
