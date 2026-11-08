Support pagination for ListEnvironments
Hey,

Would you consider supporting pagination for the ListEnvironments method? I appreciate that it is probably an edge case request but it would be nice to be able to pass in opts to the request for pagination in the instance where you have a lot of environments.


`func (s *RepositoriesService) ListEnvironments(ctx context.Context, owner, repo string, opts *ListOptions)`

### Additional contract requirements

The exact public signature of the method is:

`func (s *RepositoriesService) ListEnvironments(ctx context.Context, owner, repo string, opts *EnvironmentListOptions) (*EnvResponse, *Response, error)`

The `opts` parameter is of type `*EnvironmentListOptions` (which embeds `ListOptions` with `Page` and `PerPage`), not `*ListOptions`, and it may be nil. When `opts` is nil the request must still succeed and must not send any pagination query parameters.
Pagination is transmitted as the `page` and `per_page` query parameters.
