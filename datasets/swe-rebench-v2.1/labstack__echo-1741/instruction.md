"any" routing bug if path and any route share prefix
### Issue Description

#1563 introduced a bug where the wrong route is selected if there's an any route for a folder e.g. `/users/*` and a requested path has the folder as a prefix e.g. `/users_prefix/`.

Having the following two any routes registered:
`/*`
`/users/*`

### Expected behaviour

GET `/users` => `/*`
GET `/users/` => `/users/*`
GET `/users_prefix` => `/*`
GET `/users_prefix/` => `/*`

### Actual behaviour

GET `/users` => `/*`
GET `/users/` => `/users/*`
GET `/users_prefix` => `/*`
GET `/users_prefix/` => `/users/*` which is wrong

### Version/commit

6119aecb16b39eae121ef620d665ca0ff00b21ba

### Additional contract requirements

- The wildcard parameter `*` must have these values: GET `/` => `""`; GET `/users` => `"users"`; GET `/users/` => `""`; GET `/users_prefix` => `"users_prefix"`; GET `/users_prefix/` => `"users_prefix/"`.
