with statements aren't typechecked
There is no `visit_With` or `visit_AsyncWith`.

### Additional contract requirements

- An object used in a `with` or `async with` statement that does not satisfy the
  context manager protocol must be reported with the diagnostic code
  `invalid_context_manager`.
