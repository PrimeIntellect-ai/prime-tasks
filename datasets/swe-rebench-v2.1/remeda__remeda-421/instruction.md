`debounce` utils
For example, I'd like to delay state update when input value changes,
have any plans to implement debounce utils?

### Additional contract requirements

- `debounce` is exported from the package entry point. `debounce(func, { waitMs })` returns a debouncer object whose `call` method accepts the same arguments as `func`.
- While calls keep arriving less than `waitMs` milliseconds apart, `func` is not invoked. Once `waitMs` milliseconds pass without a new call, `func` is invoked exactly once, with the arguments of the most recent call.
