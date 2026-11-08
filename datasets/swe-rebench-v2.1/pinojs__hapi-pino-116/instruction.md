proposal for a new option: ignoreFunc
Currently hapi-pino provides `ignorePaths` and `ignoreTags`. They are useful to a certain degree, but for some cases it's still impossible to silent hapi-pino for some routes.

The use case I have in mind are routes for static files (which are usually defined with `path: /foo/bar/{file*}`). I want those to be silent. I can add a tag to these routes and use that tag in `ignoreTags`. That will work for the "request completed" log, however the "request start" log will still happen (because that log is defined in the `onRequest` extension point, and at that point the route is not yet located).

I'd like to propose a 3rd ignore option:
```
options.ignoreFunc: (options, Request) => boolean
```

[HIDDEN]

These 3 ignore options wouldn't be compatible obviously (either use `ignorePaths`/`ignoreTags` or `ignoreFunc`).

This way hapi-pino would provide the maximum flexibility to the user. If there's interest in this feature I would make a pr.

Thanks for considering.

### Additional contract requirements

- `options.ignoreFunc` is invoked with the plugin options object as its first argument and the incoming Hapi `Request` as its second argument. The first argument is the options object supplied when registering the plugin.
- When `options.ignoreFunc` returns `true`, logging for that request is suppressed; when it returns `false`, normal logging proceeds.
- When `options.ignoreFunc` is present, its result alone determines whether logging is ignored; `ignorePaths` and `ignoreTags` apply only when `ignoreFunc` is absent.
