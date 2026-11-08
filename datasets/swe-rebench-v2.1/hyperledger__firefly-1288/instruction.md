Cache not cleared on dynamic reload of namespaces
With dynamic config reload enabled:
1. Create a namespace
2. Register your multi-party organization
3. Delete the namespace in the configuration
4. Define a new namespace that happens to have the same name, with new configuration
5. Register your multi-party organization

The behavior of (5) above is non-deterministic, as it might use cache data that was the result of (2).

As such, we need to ensure we purge the caches in any case where we detect a deletion or config-change to a namespace, in the dynamic config logic.
