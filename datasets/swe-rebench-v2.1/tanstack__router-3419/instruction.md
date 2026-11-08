Path params do not support `%`
### Which project does this relate to?

Router

### Describe the bug

This is a two-fold issue.
- `navigate()` does not support path params with `%`
- The router cannot resolve paths with `%25`

### Your Example Website or App

https://stackblitz.com/edit/github-dnzkk3ai?file=src%2Froutes%2Findex.tsx

### Steps to Reproduce the Bug or Issue

### Regarding `navigate()`:
`navigate()` will throw `URI malformed` if a param contains `%`.
Example: `navigate({..., params: {q: "100%"}})`
Example: `<Link to="100%">` and `<Link to="/$q" params={{q:"100%"}}>`

**Working around the issue**
This can be circumvented by manually encoding (though I would expect the library to handle this).
Example: `navigate({..., params: {q: encodeURIComponent("100%")}})` - (`q` then becomes `"100%25"`)

The latter will successfully pushState, although the `%` ends up double-encoded.
Example: `http://website.com/search/100%2525`

`useParams` does successfully double-decode, so `const params = useParams()` yields `{q: "100%"}`

However..

### Regarding route resolution
The router cannot resolve paths (unless pushState) containing `%25` nor `%2525`.
Examples:
`http://website.com/search/100%25` - throws `URI malformed` in SSR
`http://website.com/search/100%2525` - works in SSR but throws `URI malformed` client side

### Expected behavior

- I would expect `navigate` to handle URI encoding of `%` for me.
- I would expect the URL to not need double-encoded `%2525`.
- I would expect the router (SSR and CSR) to be able to handle `%25` in path.

### Screenshots or Videos

_No response_

### Platform

- OS: macOS
- Version: 1.102.5


### Additional context

Related PR for handling `%` in query-params: https://github.com/TanStack/router/pull/3381
