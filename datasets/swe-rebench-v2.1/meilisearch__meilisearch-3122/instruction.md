Implement the details on the dump tasks
**Describe the bug**
With the big refactor of the index-scheduler it looks like we forgot to implement the details of the dump tasks.


**To Reproduce**
Steps to reproduce the behaviour:
1. Create a dump

------
BUT, we want to update when we display the `dumpId`, since it's confusing to provide a `dumpId` when the task is `enqueued` or `failed`. We're only going to set the details when the task succeeds, and something is effectively written on disk.
This is more consistent with the other tasks.
It's breaking since it wasn't implemented like that in the previous release, but it was already specified for the previous release and had simply been missed.
poke @curquiza

See this little description by @gmourier:
- `enqueued`  -> Obj `details` with `dumpUid` being null
- `processing`  -> Obj `details` with `dumpUid` being null
- `succeeded`  -> Obj `details` with `dumpUid` being specified
- `failed`  -> Obj `details` with `dumpUid` being null
- `canceled` -> Obj `details` with `dumpUid` being null
