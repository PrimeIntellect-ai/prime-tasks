Unsafe to close channel after calling Conn.RemoveSignal
If one part of my program is no longer interested in receiving D-Bus signals, it can call `RemoveSignal` to unregister the channel it provided.  At this point it would make sense to close the channel to release its resources.

However, if the channel is unbuffered or the buffer has filled up, this can lead to a panic.  While the RWLock should prevent new signals from being delivered to the channel, we could have goroutines waiting to send old signals on the channel:

https://github.com/godbus/dbus/blob/master/default_handler.go#L263-L269

It looks like the only thing that will cause these goroutines to clear is `defaultSignalHandler.Terminate`, which won't be called until the program is exiting.

The only way to avoid this seems to be to choose a channel buffer large enough that no goroutines will be spawned to handle signal broadcasts in the time it takes to acquire the write lock.  That's going to give a program that works most of the time, but may panic under load.

### Additional contract requirements

After `Conn.RemoveSignal` returns, no pending signal delivery may send to that removed channel, so the caller can safely close it. Removing one channel must not stop later signal delivery to other registered channels.
