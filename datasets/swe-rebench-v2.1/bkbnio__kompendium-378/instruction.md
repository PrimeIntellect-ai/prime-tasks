Support nested routes for Resources plugin
**Is your feature request related to a problem? Please describe.**
I am using the Ktor Resources plugin in a nested route, like this:

```kotlin
@Serializable
@Resource("/config")
object ConfigRequest

routing("/api") {
  get<ConfigRequest>() {
    ...
  }
}
```

When using `NotarizedResources()`, the generated path will show `/config`, without the `/api` prefix, while Ktor will instead serve the resource at `/api/config`.

**Describe the solution you'd like**
A way to notarize a map of resources in a given route

### Additional contract requirements

- Add a public route-scoped plugin `NotarizedResource` in package `io.bkbn.kompendium.resources`. It is an object used as
  `NotarizedResource<T>()`, where `T` is a class annotated with Ktor's `@Resource`, and installed on a `Route`, for
  example `install(NotarizedResource<MyResource>()) { ... }`.
- Installing the plugin registers the resource's OpenAPI path by combining the route's existing path with the resource's
  path, including the paths of any parent resources, matching the path at which Ktor serves the resource.
- The plugin's configuration exposes the same OpenAPI metadata as `NotarizedRoute`, including `parameters` (the list of
  path parameters) and per-method documentation such as `get`.
