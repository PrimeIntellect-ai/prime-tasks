Data channels do not fully close when close initiated from Chrome
In my application where Pion is offering and Chrome is answering:
- Pion application starts a datachannel
- The Javascript in Chrome explicitly closes the datachannel
- Pion receives the datachannel onclose event
- But Chrome's data channel stays in the "closing" state and is never "closed".

Perhaps pion is not doing https://tools.ietf.org/html/draft-ietf-rtcweb-data-channel-13#section-6.7 correctly when the close is initiated remotely?

Using pion/sctp v1.7.11

@Sean-Der suggested I reference @enobufs as you might know if this is expected behaviour

### Additional contract requirements

When a remote peer initiates a data-channel close, the local peer must handle the reset so the remote data channel can complete its transition from closing to closed. A stream exposes its lifecycle through `Stream.State()`: it reports `open` when created, `closing` after `Close()` while awaiting the peer reset, and `closed` once that reset is handled. After a stream is closed with `Stream.Close`, a subsequent write to that stream must be rejected with an error.
