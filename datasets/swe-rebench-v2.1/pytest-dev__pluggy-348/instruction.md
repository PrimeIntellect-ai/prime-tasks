`PluginManager.subset_hook_caller` can cause high memory usage
`subset_hook_caller` creates a `HookManager` which excludes calls to a set of a plugins.

A major user of `subset_hook_caller` is pytest, for its conftest mechanism - conftest plugins not relevant for a given path are excluded. pytest calls `subset_hook_caller` quite a lot, usually using the `HookCaller` and immediately throwing it away. In pytest, the lifetime of the subset `HookCaller` is much shorter than the `PluginManager`.

pluggy however needs to handle the following scenario:

1. `subset_hook_caller` is called: `shc = pm.subset_hook_caller(..)`
2. A certain (non-excluded) plugin is unregistered: `pm.unregister(plugin)`.
3. The subset `HookCaller` is called: `shc.mymethod(...)`.

In step 3, `plugin` must not be called since it was unregistered in step 2. This means that the subset `HookCaller` must still be attached to the `PluginManager` somehow. [HIDDEN]

https://github.com/pytest-dev/pluggy/blob/2b9998a277714b8ac99329e7ea5ce5908a1a89d7/src/pluggy/_manager.py#L453-L455

Alas, once the hookcaller is added to this dict, it is never removed; hence the memory is only released when the entire `PluginManager` is gone, not when the lifetime of just the subset `HookCaller` is done.
