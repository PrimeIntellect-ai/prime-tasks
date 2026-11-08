Routing Bug or Feature?
### Issue Description

Before v4.1.15 these routes used to satisfy both "/articles", "/articles/" and "/articles/whatever" URLs.
```
		"/articles",
		"/articles/*",
```
### Checklist

- [X] Dependencies installed
- [X] No typos
- [X] Searched existing issues and docs

### Expected behaviour
```
		"/articles",
		"/articles/*",
```
satisfy both "/articles", "/articles/" and "/articles/whatever" URLs.

### Actual behaviour

Since v4.1.15 now the list of routes to satisfy required behavior is this:
```
		"/articles",
		"/articles/",
		"/articles/*",
```
### Version/commit

v4.1.15


Please confirm whether this is a new behavior or bug or there's a better way of handling this scenario.

### Additional contract requirements

- With `/assets/*` registered and no `/assets` route, `/assets` must not match `/assets/*`, while `/assets/` must match it with an empty `*` parameter.
- When `/users` and `/users/*` are registered, a request to `/users/` must report `/users/*` through `Context.Path()`. When `/img/load` and `/img/load/*` are registered, a request to `/img/load/` must report `/img/load/*` through `Context.Path()`.
