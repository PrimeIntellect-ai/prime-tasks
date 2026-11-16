target() cannot be called outside a hypothesis test
I have a test `assert_allclose_phase` which checks whether two arrays are almost equal modulo one. When running under `hypothesis`, this seems like a sensible place to put `target`, albeit with a(n optional?) `name` argument in case I want to call it twice in the same test. Unfortunately if I do so then I can't use the same function in non-`hypothesis` tests:

```
E           hypothesis.errors.InvalidArgument: Calling target() outside of a test is invalid.
```

My current workaround is to call `target` only if `name` is provided, but this clutters simple tests that wouldn't need a `name`.

### Additional contract requirements

Add a public function `currently_in_test_context()` in module `hypothesis.control`, also importable as `hypothesis.currently_in_test_context`. It takes no arguments and returns a boolean: `True` when called from inside an active `@given`-decorated or stateful test, and `False` otherwise. The result reflects the calling thread's Hypothesis test context, so calling it from another thread while a test is running returns `False`.
