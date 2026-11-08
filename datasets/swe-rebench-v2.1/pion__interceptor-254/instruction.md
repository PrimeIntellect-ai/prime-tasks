Jitter Buffer error
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  FAQ of common issues and questions https://github.com/pion/webrtc/wiki/FAQ

  Free book that covers general WebRTC https://webrtcforthecurious.com/

  Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: *v0.1.29 and main branch*

### What did you do?
I push and pop packets to the Jitter Buffer.

### What did you expect?
If I added N packets then I can get N packets.

### What happened?
If I pushed packet with a SequenceNumber equal MaxUint16, then I won't be able to pop it. Packets with this SequenceNumber are possible.

I think the problem is in the following [code](https://github.com/pion/interceptor/blob/142f17f90b527434b62ce2fd92676e6e262cd807/pkg/jitterbuffer/jitter_buffer.go#L218) and similar.

@thatsnotright Have a look, please.
