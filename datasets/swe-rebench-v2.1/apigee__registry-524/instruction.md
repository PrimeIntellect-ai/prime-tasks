Support nested queries of resource revisions
Right now you can query lists of nested resources using `-`s in the parent name. For example, you can get a list of all versions from all APIs in the system by setting `parent` to `projects/my-project/locations/global/apis/-` in the `ListApiVersionRequest`.

It would be nice to have the ability to query a list of all `ApiSpec` revisions in a similar way to prevent the need for multiple nested calls to get a full revision history of an API.

### Additional contract requirements

- A resource name containing `-` for project or API identifiers must return ApiSpec revisions from every matching project or API scope, as well as supporting wildcard version and spec identifiers.
- A wildcard query must return the complete revision history for every ApiSpec that matches the resource name, not only its latest revision.
