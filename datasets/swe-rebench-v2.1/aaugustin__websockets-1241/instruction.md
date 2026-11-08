Stop listening for new connections for graceful stopping of server
Hello,

We're busy moving from tornado to websockets, and it looks like we can do almost everything, but much simpler.  Great!

There is one thing I can't seem to get going: make the server stop listening for new connections, but keep current connections open until the last client exists, then finally exit altogether.  I can keep track of current clients, but I can't seem to be able to prevent new clients from connecting.

So my idea for super graceful shutdown is:
 - stop accepting new connections
 - keep handling existing connections from clients, until they exit
 - if there are no more clients, shutdown and exit

I've experimented with the server's `close()`, which seems to disconnect existing clients, and `await wait_closed()`, which, in my case does nothing, but I suppose it is meant to be used after a normal server `close()`.  I can't find anything like tornado's `stop()`.

Any ideas how I could accomplish this?

Thanks!

### Additional contract requirements

- The server's `close()` method accepts an optional `close_connections`
  argument that defaults to `True`. When `close_connections` is `False`, the
  server stops accepting new connections while keeping already-established
  connections open until they close normally. `close()` returns `None`.
- During graceful shutdown, `wait_closed()` doesn't complete until existing
  connections and their handlers have finished.
