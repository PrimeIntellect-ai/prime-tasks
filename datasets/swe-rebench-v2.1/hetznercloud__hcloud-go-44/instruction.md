Implement listing actions
https://docs.hetzner.cloud/#resources-actions-get

### Additional contract requirements

- Add a public type `ActionListOpts` in package `hcloud` that carries the pagination options `Page` and `PerPage`.
- Add a public method `func (c *ActionClient) List(ctx context.Context, opts ActionListOpts) ([]*Action, *Response, error)` in package `hcloud`. It retrieves a single page of actions, passing `Page` and `PerPage` as query parameters, and returns the actions on the requested page, the HTTP response details, and an error if the request fails or the response cannot be decoded.
- Add a public method `func (c *ActionClient) All(ctx context.Context) ([]*Action, error)` in package `hcloud`. It retrieves all actions across all pages and returns an error if any page request fails.
