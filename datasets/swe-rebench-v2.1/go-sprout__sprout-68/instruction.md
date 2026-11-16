bug: multiple build occur growing wrapped function
### Describe the bug

I discover during the test of v0.6.0-rc1 something crazy, when we `handler.Build()` on a fresh handler all are good, but if we turn on safe mode and call `.Build()` multiple times, the wrapper will wrap again causing a wrapping loop (and also a memory grow).

### To Reproduce

1. Define a sprout handler
2. Enable safe mode (`sprout.WithSafeFunctions()`)
3. Execute multiple time `handler.Build()`
4. Show wrapped function growing N times (N are the count of `.Build` call)

### Expected behavior

When we re-call Build on an already builded function map, nothing must happend.

### Code Snippet

_No response_

### Version of software

v0.6.0-rc1

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct
