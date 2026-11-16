Propagating cancellation through threads
While writing up #607, I was thinking about a neat feature that curio has. I'm not sure if it's very important, but I envy it a bit, so I might as well open an issue to dump thoughts out where we can see them.

The feature is: say you use `run_sync_in_worker_thread` to enter a thread, and then from the thread you use `BlockingTrioPortal.run` to re-enter trio. So conceptually, this is all one stack, that starts in trio, goes into a thread, and then goes back into trio. Now suppose the original `run_sync_in_worker_thread` is cancelled. It would be neat if this caused the code inside the `BlockingTrioPortal.run` call to raise a `Cancelled` error that propagated all the way back out of trio, through the thread, and back into trio.

See #607 for more details about why this is tricky, and hard to fix even by extending the current cancel API.

I guess either we need some way to reenter a given cancel binding (which feels very weird and unlikely to have other use cases), or else some way to capture the exception in `run_sync_in_worker_thread` (<- this part we have) and then inject it into the eventual task (<- this part we don't have). Well... [HIDDEN] (We could even fudge the traceback if we want to be really tricky.) Or... we could switch from attaching `Cancelled` objects to specific scopes/bindings, and make it so that each `with` block checks if it is associated with the outermost cancelled scope, and if so it catches all `Cancelled` exceptions, and then it would be fine to manually capture a `Cancelled` from inside the re-entry task and pass it over to the thread, before it gets caught. Except, ugh, that won't work if the exception isn't `Cancelled` but rather `KeyboardInterrupt`.

[HIDDEN]

Alternatively... can we avoid all this rigmorale? [HIDDEN] Then any cancel scope that contained the `run_sync_in_worker_thread` call would also automatically contain any re-entry tasks.

`KeyboardInterrupt` might still require some careful handling, since it doesn't follow the normal cancel scope scoping rules. I guess we could do some shenanigans like pushing the actual wait-for-thread into a child task? Actually this would be pretty simple: open nursery, start a child to do the actual thread waiting stuff, then park in the nursery `__aexit__` – `KeyboardInterrupt` will be delivered to `__aexit__` and cause the nursery to be cancelled. (Actually, this is an interesting possible strategy for delivering `KeyboardInterrupt` in general: pick a nursery and inject it directly there, as if it were raised by a task inside that nursery. Or do this to the system nursery, though that feels weird.) I'd be a *little* nervous about adding overhead to `run_sync_in_worker_thread`, but maybe it wouldn't be that bad.
