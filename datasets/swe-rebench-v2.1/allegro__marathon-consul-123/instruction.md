Set initial consul health check to passing
Consul allows setting initial health check value. Since we know that application is working (we register only when Marathon health check is passing) we can minimize time when service is unavailable in consul by setting health check to passing when registering service.

https://github.com/hashicorp/consul/issues/2314#issuecomment-248630431

### Additional contract requirements

- When registering a service, initialize each Consul health check created from a Marathon health check with its `Status` field set to `"passing"`; this field represents the check's initial health-check value.
