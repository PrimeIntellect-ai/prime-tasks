nil pointer dereference in RTPReceiver readRTP
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  FAQ of common issues and questions https://github.com/pion/webrtc/wiki/FAQ

  Free book that covers general WebRTC https://webrtcforthecurious.com/

  Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: *v3.2.40*
```
[signal 0xc0000005 code=0x0 addr=0x18 pc=0x7ff724f803d7]

goroutine 129 [running]:
github.com/pion/webrtc/v3.(*RTPReceiver).readRTP(0xc000414d80, {0xc000150600, 0x5b4, 0x5b4}, 0xc00077ea20)
        C:/Users/teng.lee/go/pkg/mod/github.com/pion/webrtc/v3@v3.2.40/rtpreceiver.go:369 +0xf7
github.com/pion/webrtc/v3.(*TrackRemote).Read(0xc00077ea20, {0xc000150600, 0x5b4, 0x5b4})
        C:/Users/teng.lee/go/pkg/mod/github.com/pion/webrtc/v3@v3.2.40/track_remote.go:139 +0x24e
github.com/pion/webrtc/v3.(*TrackRemote).peek(0xc00077ea20, {0xc000150600, 0x16?, 0x5b4})
        C:/Users/teng.lee/go/pkg/mod/github.com/pion/webrtc/v3@v3.2.40/track_remote.go:191 +0x26
github.com/pion/webrtc/v3.(*PeerConnection).startReceiver.func1(0xc00077ea20)
        C:/Users/teng.lee/go/pkg/mod/github.com/pion/webrtc/v3@v3.2.40/peerconnection.go:1241 +0x7a
created by github.com/pion/webrtc/v3.(*PeerConnection).startReceiver in goroutine 105
        C:/Users/teng.lee/go/pkg/mod/github.com/pion/webrtc/v3@v3.2.40/peerconnection.go:1239 +0x1e5
exit status 2
```

### What did you do?

Run pion with unsupported codec at remote? I'm not sure how to pin point the problem

### What did you expect?

ignore error and continue running

### What happened?

nil pointer dereference and panic

### Temporary solution

[HIDDEN]

[HIDDEN]

### Additional contract requirements

- A failed `RTPReceiver.Receive` must not cause subsequent RTP reads to panic; the failure must be handled as an error so the application can continue and shut down normally.
- When `RTPReceiver.Stop` is called, waiting or subsequent calls to `RTPReceiver.Read` and `TrackRemote.ReadRTP` must return `io.ErrClosedPipe`, including when `Receive` previously failed.
