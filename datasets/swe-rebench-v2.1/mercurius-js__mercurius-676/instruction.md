Allow setting graphql-jit's customJSONSerializer / fast-json-stringify
I'd like to use graphql-jit's `customJSONSerializer` option, to use `fast-json-stringify` instead of `JSON.stringify`, but it looks like that isn't possible:

https://github.com/mercurius-js/mercurius/blob/361e9534f8c5e0dd693e16c7943b74b0d4c20e1e/index.js#L483

Could this be supported by mercurius's API?

I'm also a little curious if `customJSONSerializer` should just always be passed true, i.e. if its faster, just have that be the default. I had actually assumed it was, and was surprised that neither graphql-jit nor mercurius default it to on.

I guess `fast-json-stringify` does have the disclaimer that its slower on large output (...or at least "not as dramatically faster"), so maybe that is why.

Kind of random/tangential, I also noticed the `fast-json-stringify` disclaimer about it dove-tailing really well with `flatstr`, but I don't see `flatstr` used in either mercurius or graphql-jit; is that a missed opportunity for a performance win?

### Additional contract requirements

- Mercurius accepts a `compilerOptions` object in the plugin options. When `jit` is enabled and Mercurius JIT-compiles a query, the object is forwarded to graphql-jit's compiler, so a user can enable graphql-jit's `customJSONSerializer` option through the Mercurius API (for example `compilerOptions: { customJSONSerializer: true }` alongside `jit: 1`).
