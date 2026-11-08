Too many API requests for outdated routes in the network
### TL;DR

A  lot of calls to `client.Server.All()` are being made when the network has a lot of "outdated" routes for IPs that no longer belong to an active server.

### Expected behavior

HCCM should not spam the API in reasonable situation.

### Observed behavior

In `RouteController.ListRoutes()` we try to match every route in the network to the correct Kubernetes node.

For this, we check if the Gateway IP of the route matches the known internal IP of the any server in the network.

To make this more efficient, there was a cache introduced that provides access to the server list. This works great when the server is actually in the cache.

If no server can be found in the cache, we assume that our cache is outdated and refresh the cache with the API.

This refresh is repeated once for every route that has no matching server.

### Minimal working example

- Add x bogus routes in the Cluster CIDR to the Network before starting HCCM.
- Observe x calls to `GET /v1/servers`


### Log output

_No response_

### Additional information

_No response_

### Additional contract requirements

In package `internal/hcops`, `hcops.AllServersCache` must expose a `CacheMissRefreshLimiter` field of type `*rate.Limiter` (from `golang.org/x/time/rate`).
