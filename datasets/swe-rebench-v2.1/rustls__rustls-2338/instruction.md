unbuffered: No way to refuse a ReadTraffic if there is no space
**Checklist**
* [x] I've searched the issue tracker for similar bugs.

**Describe the bug**

The scenario is that Rustls unbuffered is being used between four fixed-sized buffers (in/out on each side), each of which might have a varying level of fill depending on downstream/upstream processing. So depending on the size of the record being decoded, there might not be space to output the results. In simple terms both data to decode and space to put the result must be present before a Rustls operation can occur successfully.

ReadTraffic appears to support this in terms of having a `peek_len` method to get the length that is required. If there is not space, presumably the intention is that I should not call `next_record` and I shouldn't apply the `discard`.  However even if `next_record` is not called, the operation already seems to have been committed to, and the data is lost.

**To Reproduce**

The code I have to reproduce this is in a couple of crate versions which aren't published. I'd have to give you a TGZ.

**Applicable Version(s)**

0.23.10 on Linux

**Expected behavior**

If the intention of unbuffered is to allow working with fixed-size buffers, then there always needs to be a way to refuse an operation if the caller doesn't have enough space to store the result. So I'd expect that if I didn't commit (via `next_record` or whatever) then the operation wouldn't be commited internally in Rustls either. But it's not the details of the API that are important, but just having the means to handle the situation. If there was some other way to check how much space is required at some other point, e.g. before calling `process_tls_records`, that would also be okay. Even something like "don't call it unless you have 32KB free in both outgoing buffers". That's more wasteful but could also work.

**Additional context**

I think it may be worth putting unbuffered under a cargo feature (e.g. "beta") and specifying that it isn't under semver, to give you some flexibility to iterate until things are more solid.

I also have some difficulties with WriteTraffic, but more solvable. Since in this scenario my output buffers may be fixed-size but not fully allocated, I don't want to reallocate the buffers to the maximum unless really necessary. So I need to estimate how much space you require for the `WriteTraffic::encrypt` call. So I'm estimating 100 bytes more than the unencrypted data length. This mostly works, but sometimes I was seeing much larger requirements in terms of InsufficientSize being returned. It seems that other stuff may get included in the write unrelated to the data I'm sending, which I can't account for in my estimate.

Also, when my output space is limited, I was attempting to send data 100 bytes shorter than the space I have free. But this may be complicated by the other stuff that Rustls wants to send. I tried to back off if I get a failure, and send zero bytes to a zero-sized buffer get a measurement of the hidden data that needs sending. However I have not yet fully debugged this code because of the issues on the ReadTraffic side.

So it may be helpful to have better documentation on buffer sizing requirements and the expectations that Rustls has of the caller.

Again, as with the other issue (#1895) there is no rush. I'm trying to implement this to test the feasibility of running with fixed-sized buffers. But I don't have a deadline.

### Additional contract requirements

- Application data that has been received must not be consumed until the caller explicitly takes it. Inspecting the length of the next available record must not remove it, and the same record must remain available to be read on a later call.
