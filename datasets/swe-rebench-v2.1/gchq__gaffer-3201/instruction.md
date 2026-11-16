Add config options to disable named operations and named views
**Describe the new feature you'd like**
To make configuration more obvious, it should be possible to explicitly disable named operations and named views, instead of having to do this by omitting cache configuration for them.

**Why do you want this feature?**
In #3147 it was noticed that the job tracker can be enabled and disabled (by default disabled), but the same is not true for named operations and named views (by default enabled). Although they are enabled by default, they cannot be used if no cache class has been configured.

This has led to situations where the cache has been disabled so that named operations are disabled. With the changes in #3147 it is possible to use distinct kinds of cache for named operations, named views, federated stores and jobs. This makes it possible to use just one of these services by configuring the cache for only this service.

**Describe alternatives you've considered**
Omitting cache configuration for named operations and named views to disable them, which is less clear.

**Additional context**
This also allows for removing some less readable logic blocks using `CacheServiceLoader.isEnabled` from `Store.java`.

### Additional contract requirements

Expose the named-operation enable control through `StoreProperties.getNamedOperationEnabled()` and `StoreProperties.setNamedOperationEnabled(boolean)`, and expose the named-view enable control through `StoreProperties.getNamedViewEnabled()` and `StoreProperties.setNamedViewEnabled(boolean)`. Both controls default to enabled. Disabling either named service must not prevent the other named service from being used, and the enabled service must not require cache configuration for the disabled service.
