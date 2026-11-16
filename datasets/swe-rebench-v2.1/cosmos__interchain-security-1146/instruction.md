Incorrect method of deleting pending consumer packets
<!-- < < < < < < < < < < < < < < < < < < < < < < < < < < < < < < < < < ☺
v                            ✰  Thanks for opening an issue! ✰
v    Before smashing the submit button please review the template.
v    Please also ensure that this is not a duplicate issue :)
☺ > > > > > > > > > > > > > > > > > > > > > > > > > > > > > > > > >  -->

## Summary of Bug

While developing I found a hopefully minor bug in how the consumer commits packets. From my analysis this bug is NOT of critical severity.

In [SendPackets](https://github.com/cosmos/interchain-security/blob/6e3164cb695de004207b54fa36878f0b2f8412aa/x/ccv/consumer/keeper/relay.go#L179) we iterate over a list of pending packets, and if an error is returned for _any_ of the packets, the entire method is returned, and none of the pending packets are deleted.

This means that if you're sending 2 pending packets, the first one sends successfully, and the second packet does not, then neither packet is deleted. The next block, both packets will be attempted to be sent again, possibly causing a duplicate send.
Why is this not critical imo? An error being returned from SendIBCPacket would indicate a deeper issue, likely with IBC. Also it looks like the provider can handle duplicate Slash/VSCMatured packets without panic.

Regardless, this bug is worth fixing in case provider or IBC functionality changes.

## Version

b7a0d1d4806d65265342f21cc23fc73495c055e2

## Steps to Reproduce

n/a

#### For Admin Use

- [ ] Not duplicate issue
- [ ] Appropriate labels applied
- [ ] Appropriate contributors tagged
- [ ] Contributor assigned/self-assigned
- [ ] Is a spike necessary to map out how the issue should be approached?
