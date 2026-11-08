NACK generator interceptor implements `BindRemoteStream` but `UnbindLocalStream`
I assume it should instead implement `UnbindRemoteStream`?

### Additional contract requirements

- When a remote RTP stream is removed, the NACK generator must stop tracking that stream's SSRC, so no further NACK feedback is generated for it.
