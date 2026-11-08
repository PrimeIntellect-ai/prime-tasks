feat: Make sure all Clients have .AllWithOpts method
We recently realized that some clients are missing the `.AllWithOpts` method (see #254). This is still missing for other clients:

- `DatacenterClient`
- `LoadBalancerTypeClient`
- `LocationClient`
- `ServerTypeClient`

### Additional contract requirements

- `DatacenterClient.AllWithOpts(ctx context.Context, opts DatacenterListOpts) ([]*Datacenter, error)` in package `hcloud`.
- `LoadBalancerTypeClient.AllWithOpts(ctx context.Context, opts LoadBalancerTypeListOpts) ([]*LoadBalancerType, error)` in package `hcloud`.
- `LocationClient.AllWithOpts(ctx context.Context, opts LocationListOpts) ([]*Location, error)` in package `hcloud`.
- `ServerTypeClient.AllWithOpts(ctx context.Context, opts ServerTypeListOpts) ([]*ServerType, error)` in package `hcloud`.
- Each method honors the supplied list options and returns all matching items across pages, continuing pagination until no further page is indicated.
