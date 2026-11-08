proposal: add an IP address classification mechanism
I make pretty frequent use of a few of the stdlib's IP address classification methods:

```
    func (ip IP) IsGlobalUnicast() bool
    func (ip IP) IsInterfaceLocalMulticast() bool
    func (ip IP) IsLinkLocalMulticast() bool
    func (ip IP) IsLinkLocalUnicast() bool
    func (ip IP) IsLoopback() bool
    func (ip IP) IsMulticast() bool
    func (ip IP) IsUnspecified() bool
```

I'm not sure all of these are necessary in something like netaddr, but I do think there should be a mechanism for determing the properties of an address.

I came up with a few ideas:

1) add methods like the stdlib does today

The unfortunate thing here is that you end up with a potentially more bloated API, and it's difficult to draw the line on where to stop adding methods. What about IPv6 unique local addresses for example?

2) expose a bit flags API and a set of constants, akin to net.Flags

This method is pretty concise but may require a bit of processing to return the bit flags set. Once the flags are returned, you have to check them with bit ops which @danderson and I both tend to find unappealing.

```go
ip := mustIP("fe80::1")
if ip.Properties()&netaddr.LinkLocalUnicast != 0 {
    fmt.Println("is link-local unicast")
}
```

3) return a struct with boolean fields for a more concise API and easier use

The disadvantage here is the need to allocate a structure and do some work every time the method would be called.

```go
ip := mustIP("fe80::1")
if ip.Properties().LinkLocalUnicast {
    fmt.Println("is link-local unicast")
}
```

---

Any other ideas?

I am leaning toward option 1 (do what stdlib does) as it seems to be the most reasonable tradeoff between readability, performance, and allocations, even if it means sacrificing some conciseness in the exported API.

### Additional contract requirements

`IP.IsMulticast` reports whether an IP address is multicast. It returns true for multicast IPv4 and IPv6 addresses, and false for non-multicast addresses, including the zero-value `IP`.
