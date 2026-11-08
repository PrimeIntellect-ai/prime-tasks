WriteTo() on relay conn (net.PacketConn) returns incorrect number of bytes sent

### Your environment.
  - Version: v2.0.8
  - Browser: *include version*
  - Other Information - *stacktraces, related issues, suggestions how to fix, links for us to have context*

### What did you do?
Sent data from TURN client to a peer.

### What did you expect?
Passing buffer with size N to relayConn.WriteTo() should return N on success.

### What happened?
Returned number is slightly longer than what the given buffer size was.

```
    turn_server_test.go:330: relayConn0: sent 1024 (1028) bytes to 127.0.0.1:52277
    turn_server_test.go:337: relayConn1: sent 1024 (1028) bytes to 127.0.0.1:54472
```
