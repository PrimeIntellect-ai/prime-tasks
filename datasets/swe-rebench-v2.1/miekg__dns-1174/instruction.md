Allow any net.PacketConn and don't assume it is *net.UDPConn
When using this project in combination of a userland tcpip stack, we don't have a *net.UDPConn but a custom net.PacketConn. It would be great to be able to start the DNS server.

The use case will be to add a built-in DNS server in https://github.com/majek/slirpnetstack/ or in https://github.com/code-ready/gvisor-tap-vsock

Links:
tcpip stack: https://github.com/google/gvisor/tree/master/pkg/tcpip
adapter for the stack and go net interfaces: https://github.com/google/gvisor/blob/master/pkg/tcpip/adapters/gonet/gonet.go#L570
Current patch I use: https://github.com/guillaumerose/dns-1/commit/fe9b991fbece42eb3ef3a118dc043aecf1f48d1c
