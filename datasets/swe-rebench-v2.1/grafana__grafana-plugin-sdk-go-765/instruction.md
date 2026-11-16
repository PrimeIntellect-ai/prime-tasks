Instancemgmt: Instance possibly being disposed while still being in use
Follow up from https://github.com/grafana/grafana/pull/75171 and https://github.com/grafana/grafana/pull/75249 we have concluded that app/datasource instance caching works as expected given a high rate of concurrent requests. However, it seems like it's possible that `Dispose()` of a cached instance being called in a goroutine while there's another goroutine still using it. This could happen in the following way:

1. Goroutine ONE enters this code for cachekey `ABC` and get a hold of a cached instance:
https://github.com/grafana/grafana-plugin-sdk-go/blob/dd41f8d709969a5efd5375833f9754cecf9176bc/backend/instancemgmt/instance_manager.go#L92-L108
2. Goroutine TWO enters this code almost at the same time for the same cachekey `ABC`, but compared to 1) the instance needs an update and goes into this code which will call `Dispose()` of the currently active instance:
https://github.com/grafana/grafana-plugin-sdk-go/blob/dd41f8d709969a5efd5375833f9754cecf9176bc/backend/instancemgmt/instance_manager.go#L110-L137
3. Goroutine ONE continue its execution and tries to use the instance, but fails since it's already disposed.

This should theoretically only happen with a high rate of concurrent requests.

**Proposed solution:**
We're going to look into disposing instances after X amount of time has passed and/or when the instance no longer is in use.

### Additional contract requirements

- Provide an assignable package-level `disposeTTL` variable of type `time.Duration` to control the deferred-disposal delay.
- When a cached instance implementing `InstanceDisposer` is replaced, defer its `Dispose()` call rather than disposing it synchronously, and ensure disposal occurs within 10 seconds.
