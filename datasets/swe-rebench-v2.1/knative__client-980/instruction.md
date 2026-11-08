[source list] Add custom type for different types of source objects
### Feature request

`kn source list` gives you objects of different types of sources. While printing the JSON/YAML format of list, we'd need
proper values for `apiVersion` and `kind` fields of the list printed, since the objects list contains are of different types.

Current behavior, sets empty string for `apiVersion` and `List` for `kind`.
This is to track setting these fields to for eg: `apiVersion: client.knative.dev/v1alpha1`
ref: https://github.com/knative/client/pull/948#discussion_r461362683

There is also a discussion about what `apiVersion` and `kind` values should be if, the source list is of single type source OR `--type` filter is given with single type to `kn source list`, in this scenario, only single type of source objects are printed.

### Additional contract requirements

Every non-empty source list uses the custom list metadata `apiVersion: client.knative.dev/v1alpha1` and `kind: SourceList`. This applies both when the list contains different source types and when it contains one source type, including when a type filter selects that type.
