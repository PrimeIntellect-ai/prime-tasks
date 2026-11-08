proposal: add method IP.IPAddr for adapting into existing code
I am certainly a fan of the ideas being put forth by this package, but there is a massive amount of preexisting code which expects to work with net.IP/net.IPAddr exclusively.

I'd propose a method as follows:

```go
// IP returns the net.IPAddr representation of an IP. If the IP contains a zone
// identifier, the Zone field of the returned IPAddr is populated.
func (ip IP) IPAddr() *net.IPAddr
```

From there, the caller can either use the net.IPAddr directly or extract the IP address for use with APIs which expect net.IP.

I was considering proposing `IP() net.IP` instead, but due to the inclusion of the zone identifier in this package, I think this is a fair compromise.
