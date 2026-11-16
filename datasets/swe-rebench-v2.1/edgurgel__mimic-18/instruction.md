Inspecting existing stubs/expectations
I'm writing some generic code for my tests that calls Mimic's `allow/3` on `Task.async` when in the test environment, so that I can write async code without worrying whether it's going to be testable or not.

The problem is if no stubs or expectations were created for the Mock, the `allow/3` call raises since [there's no case for an empty list](https://github.com/edgurgel/mimic/blob/master/lib/mimic/server.ex#L269-L274). I'm working around this in my own code by calling `:ets` directly as if I were Mimic, but would prefer a less hacky solution.

I could do a PR for this, but there are multiple possible solutions, wondering what you think would be preferrable:

1. Adding an empty list case as a no-op in `allow`.
2. Adding an empty list case but returning an error/warning instead.
3. Exposing a function in the `Mimic` module for inspecting the existing stubs/expectations on a Mock.
4. _something else_?

Thanks!

Edit: it'd also be useful to access the currently active mode, since we can't `allow` when `:global`. I'm using `:sys.get_state(Mimic.Server)` atm as a workaround.

### Additional contract requirements

- `Task.async/1` automatically shares the stubs and expectations defined by the calling process. A process started with `Task.async/1` (including nested `Task.async/1` calls) can call a mocked module and see the calling process's stubs and expectations without calling `allow/3`.
- The supported way to handle a copied mock that has no stubs or expectations is to use `Task.async/1`, which automatically shares the calling process's configuration; `allow/3` does not need to be called in that case.
