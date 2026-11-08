ContextRegistry not finding closest path context, defaults to root due to Dispatcher bug
With an OpenApi v2 doc with a specific `basePath` the `contextRegistry.find` operation receives a path with the full `basePath` included. Since the contextRegistry entries do not include the basePath in their key it can't find any path-level contexts and defaults to the root context.
