Allow template resources to have wildcard matches
### Enhancement Description

For example, I'd like to have a resource that serves up files, and match something like `contents://{path*}` so that it would be used for `contents://foo/bar/baz.gif`. If I create a resource using `@app.resource("contents://{path}")` it only works if the path is a single file.

### Use Case

_No response_

### Proposed Implementation

```Python

```

### Additional contract requirements

- A URI template may contain multiple wildcard parameters: matching `test://a/x/y/b/c/d` against `test://a/{x*}/b/{y*}` must produce `{"x": "x/y", "y": "c/d"}`, and matching `test://a/x/y/b` against `test://a/{x*}/{y}` must produce `{"x": "x/y", "y": "b"}`.
- A wildcard template registered as a resource must be usable to serve a matching URI request: a template `contents://{path*}` must serve `contents://foo/bar/baz.gif` with `path` captured as `foo/bar/baz.gif`.
