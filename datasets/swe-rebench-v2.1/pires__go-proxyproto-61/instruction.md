Parsing v2 UNSPEC and v1 PROXY UNKNOWN not implemented
Hi! I found that this library is missing the ability to parse these two kinds of header, which are required by the protocol and mandatory to implement, while trying to resolve XTLS/Xray-core#166

### v2 UNSPEC

When this header is received:

```
0d 0a 0d 0a 00 0d 0a 51 55 49 54 0a 20 00 00 00
```

which is <v2 signature> + LOCAL command (\x20) + UNSPEC address family UNSPEC protocol (\x00)
`ErrUnsupportedAddressFamilyAndProtocol` is returned
https://github.com/pires/go-proxyproto/blob/adbbabed1f24a2123e1d4368ae8da8378b347643/v2.go#L85-L87
This is because UNSPEC is absent in supportedTransportProtocol
https://github.com/pires/go-proxyproto/blob/adbbabed1f24a2123e1d4368ae8da8378b347643/addr_proto.go#L6-L23
This UNSPEC header is used when HAProxy doing health checks, or the proxied client is requesting via a unix socket.
Also the protocol spec says:

```
Only the UNSPEC protocol byte (\x00) is mandatory to implement on the receiver.
A receiver is not required to implement other ones, provided that it
automatically falls back to the UNSPEC mode for the valid combinations above
that it does not support.
```

### v1 PROXY UNKNOWN

When header `PROXY UNKNOWN\r\n` is received,
https://github.com/pires/go-proxyproto/blob/adbbabed1f24a2123e1d4368ae8da8378b347643/v1.go#L25-L33
returns ErrCantReadProtocolVersionAndCommand.
This is because in this case, there's only 2 parts separated by spaces, instead of 6 parts as `PROXY <PROTO> <SRC_ADDR> <DEST_ADDR> <SRC_PORT> <DEST_PORT>`
The protocol spec says:
```
If the announced transport protocol is "UNKNOWN", then the receiver knows that
the sender speaks the correct PROXY protocol with the appropriate version, and
SHOULD accept the connection and use the real connection's parameters as if
there were no PROXY protocol header on the wire.
```
Also, this kind of header can be formatted by the library.
https://github.com/pires/go-proxyproto/blob/adbbabed1f24a2123e1d4368ae8da8378b347643/v1.go#L76-L88

Although I really don't know much about Golang, I'll try my best to support you to resolve this issue. Thanks!

### Additional contract requirements

- For malformed v1 headers, return `ErrInvalidAddress` when a TCP6 header contains IPv4 addresses or a TCP4 header contains IPv6 addresses, and return `ErrInvalidPortNumber` when a TCP4 header contains an invalid port.
- For malformed v2 headers, return `ErrNoProxyProtocol` for a missing or truncated signature, `ErrCantReadProtocolVersionAndCommand` for a signature without a command, `ErrUnsupportedProtocolVersionAndCommand` for an invalid command, `ErrCantReadAddressFamilyAndProtocol` for a PROXY command without a family and protocol, `ErrUnsupportedAddressFamilyAndProtocol` for a PROXY command with UNSPEC, `ErrCantReadLength` for an invalid family/protocol or missing or malformed length, and `ErrInvalidLength` when the declared length does not match the address data.
