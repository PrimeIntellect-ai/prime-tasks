Using a ResourceStore for internal storage is broken
Using the config feature `storage/key-value/resource-store.json` breaks the server. Reason being that we have a circular dependency:
 * `LockingResourceStore` uses a `GreedyReadWriteLocker`
 * `GreedyReadWriteLocker` uses a `JsonResourceStorage` for storage (when the above config is enabled)
 * `JsonResourceStorage` uses the main `ResourceStore`, which has the `LockingResourceStore` in it as second store.

This makes it impossible to instantiate the server with that config. None of the integration tests use a setup with that storage setup so this remained undetected (woops). The IDP does use that kind of storage but in that case there is no loop since the storage it uses is a different instance than the one used by the locker.

[HIDDEN]

[HIDDEN] The fact that this bypasses the locker is currently not an issue since the only class using it is the `GreedyReadWriteLocker` which already has its own locks around the requests. To be future proof we probably want at least solution 2, so there are no potential issues when multiple instances are writing to the storage. Solution 3 seems overkill since all the other stores in the store stack are irrelevant for the storage. This might change in the future of course.

### Additional contract requirements

- When `storage/key-value/resource-store.json` is enabled, the server must be instantiable without the reported circular dependency.
