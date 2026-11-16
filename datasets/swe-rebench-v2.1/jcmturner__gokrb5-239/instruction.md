types.GetHostAddress doesn't produce correct addresses
The client machine has the following addresses: `172.17.0.1, 192.168.3.225, 172.17.8.1`. The service is running locally.

This is a trace of a service trying to check host adresses contained in a ticket:

```
trace: validate APREQ: client address: 127.0.0.1:45860
trace: validate APREQ: client address: {2 [49 50 55 46 48 46 48 46 49]}
trace: validate APREQ: ticket client addresses: [{2 [172 17 0 1]} {2 [192 168 3 225]} {2 [172 17 8 1]}]
```

We do find the client IPs in the ticket, encoded as 4 bytes. `types.GetHostAddres()` encodes the client address (`127.0.0.1`) in a weird way though.`0x49 0x50 0x55 0x46 0x48 0x46 0x48 0x46 0x49` is indeed the string `"127.0.0.1"` where each character is encoded separately (and the hex value end up as base 10!).

For `127.0.0.1` I would expect `types.GetHostAddres()` to return `{2 [127 0 0 1]}`. That's what the [spec](https://tools.ietf.org/html/rfc1510#section-8.1) seems to be saying.
