Add dependancy injection for handlers
Currently the package provides a logger in a sort of DI way which is extremely useful.
I believe it should be possible to generalise this so users could add their own dependancy objects to pass to handlers when building endpoints.
I've got some code that can sort of do this already however it is not perfect yet and would be a breaking change when it shouldn't be so not ready for a pull request yet.
An example usage would be
```
new EndPointFactory(...)
  .addDependancy({db:SomeDataBaseObject})
  .build({
    input:...
    output:...
    handler: async ({input, db, logger})=>{
      db.query();
      return ...;
    }),
  });
```

Sorry for any mistakes, its 04:00 am here.
What do you think of this?
I'd also like to expand it to add dependancies that get created with a function on each request too for stuff like specific database connections instead of a single database object.

### Additional contract requirements

- Add a public method `addOptions(options)` to `EndpointsFactory` (exported from the package root, together with the default instance `defaultEndpointsFactory`). It accepts an object of arbitrary key/value pairs and returns a new `EndpointsFactory` instance, leaving the factory it is called on unchanged.
- Every endpoint built from the returned factory receives the supplied key/value pairs through the `options` argument of its handler, in addition to the logger.
