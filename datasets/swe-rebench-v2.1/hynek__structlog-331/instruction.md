Public access to threadlocal._get_context()
Similarly to #266, I find myself needing to access the thread-local context (I need to re-estabish some bound variables after a `clean_threadlocal()`).

I tried to use `structlog.get_context()` but it's not returning the threadlocal context. If this would be accepted, I might even come up with a PR.

### Additional contract requirements

- Add a public function `get_threadlocal()` in module `structlog.threadlocal` that returns the current thread-local context as a `dict`. It returns an empty dict if no context has been set, and it never raises.
- Add a public function `get_merged_threadlocal(bound_logger)` in module `structlog.threadlocal` that returns a `dict` containing the thread-local context merged with the context retrieved from `structlog.get_context(bound_logger)`.
