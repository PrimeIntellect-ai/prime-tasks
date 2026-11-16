Add concurrency endpoint for xTM
**Summary**
As users move to xTM, they will need to use a different concurrency endpoint that is made to take teams into account.

This is /rest/v1.2/users/:username/concurrency

Currently, we only provide access to rest/v1.1/users/:username/concurrency via getUserConcurrency

**AC**

Add new endpoint to sauce.json Swagger to support this new endpoint.

### Additional contract requirements

The response schema for `/rest/v1.2/users/:username/concurrency` must represent concurrency grouped by team and organization. Its concurrency map has group entries with `current` and `allowed` values; each value contains integer `mac_vms`, `rds`, and `vms` counts and a string `id`. The existing `getUserConcurrency` access must use this v1.2 endpoint.
