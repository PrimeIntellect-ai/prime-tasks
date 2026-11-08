Support "spawn" for training subprocesses
## Describe the bug

Some libraries such as `torch` have significant issues when running in a `subprocess` using the `"fork"` method. The current `DestroyableThread` [explicitly uses "fork"](https://github.com/caikit/caikit/blob/main/caikit/core/toolkit/destroyable_process.py#L18) to avoid problems with data model object not being recreated correctly, but this can break downstream usage of libraries such as `torch`.

### Additional contract requirements

When subprocess training is enabled, the local trainer's `subprocess_start_method` configuration option must support `spawn`. Training inputs must remain usable in the spawned process without depending on state inherited from the parent process.
