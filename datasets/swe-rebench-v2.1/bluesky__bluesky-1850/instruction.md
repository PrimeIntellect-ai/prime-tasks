bps.wait move_on kwarg is undocumented
This behaviour, added as part of #1641, is undocumented. According to @coretl it is to enable a `wait` that times out to not be an exception. In my opinion, it's not the best name as "wait" and "move on" are antonyms. It should be documented or self-documenting what the argument does.
If the kwarg name was amended to "allow_timeout" or similar, it might be clearer what is meant.

https://github.com/bluesky/bluesky/blob/3bce96b85558993499174be7eebcd09f270a9271/src/bluesky/plan_stubs.py#L636

### Additional contract requirements

- The `wait` plan stub accepts a keyword argument named `error_on_timeout` (boolean, default `True`).
- The `wait` message yielded by the `wait` plan stub carries that value in a field named `error_on_timeout`, replacing the former `move_on` field.
- When `error_on_timeout` is `True`, a timeout raises an exception; when it is `False`, the plan continues after the timeout.
