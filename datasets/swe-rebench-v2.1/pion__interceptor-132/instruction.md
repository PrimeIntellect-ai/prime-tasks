[SendSideBWE ] `delayController` raises panic when packet arrives after interceptor is closed
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  We also provide a Knowledge Base https://pion.ly/knowledge-base that covers Pion and general WebRTC

  We maintain a FAQ of common issues and questions https://pion.ly/knowledge-base/pion-basics/faq/

 Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: `github.com/pion/interceptor v0.1.11-0.20220401022307-09051cdde82b`
  - Other Information -

Panic stack trace:
```
runtime.gopanic
        /usr/local/go/src/runtime/panic.go:965
runtime.chansend
        /usr/local/go/src/runtime/chan.go:281
runtime.chansend1
        /usr/local/go/src/runtime/chan.go:143
github.com/pion/interceptor/pkg/gcc.(*delayController).updateDelayEstimate
        /go/pkg/mod/github.com/pion/interceptor@v0.1.11-0.20220401022307-09051cdde82b/pkg/gcc/delay_based_bwe.go:96
github.com/pion/interceptor/pkg/gcc.(*SendSideBWE).WriteRTCP
        /go/pkg/mod/github.com/pion/interceptor@v0.1.11-0.20220401022307-09051cdde82b/pkg/gcc/send_side_bwe.go:141
github.com/100mslive/ion-sfu/pkg/sfu.(*TrackAllocator).OnTransportCCFeedback
        /go/pkg/mod/github.com/100mslive/ion-sfu@v1.9.9-0.20220510151633-ae293ba3929d/pkg/sfu/track_allocator.go:459
github.com/100mslive/ion-sfu/pkg/sfu.(*DownTrack).handleRTCP
        /go/pkg/mod/github.com/100mslive/ion-sfu@v1.9.9-0.20220510151633-ae293ba3929d/pkg/sfu/downtrack.go:985
github.com/100mslive/ion-sfu/pkg/sfu.(*DownTrack).Bind.func1
        /go/pkg/mod/github.com/100mslive/ion-sfu@v1.9.9-0.20220510151633-ae293ba3929d/pkg/sfu/downtrack.go:273
github.com/100mslive/ion-sfu/pkg/buffer.(*RTCPReader).Write
        /go/pkg/mod/github.com/100mslive/ion-sfu@v1.9.9-0.20220510151633-ae293ba3929d/pkg/buffer/rtcpreader.go:25
github.com/pion/srtp/v2.(*ReadStreamSRTCP).write
        /go/pkg/mod/github.com/pion/srtp/v2@v2.0.5/stream_srtcp.go:30
github.com/pion/srtp/v2.(*SessionSRTCP).decrypt
        /go/pkg/mod/github.com/pion/srtp/v2@v2.0.5/session_srtcp.go:173
github.com/pion/srtp/v2.(*session).start.func1
        /go/pkg/mod/github.com/pion/srtp/v2@v2.0.5/session.go:141

```

### What did you do?
<!--
If possible, provide an example for reproducing the error.
A complete runnable program is good.
-->

### What did you expect?
No panics

### What happened?
There's a race between RTCP packets written to `SendSideBWE` and interceptor being closed due to which any packets written after the interceptor is closed raised the panic `send on closed channel`. This panic happens very rarely (1 out of 200 `Peer`) which makes it pretty hard to reproduce in local env. It happens at the same time when ice state goes into `closed` state and respective peer-connection is closed

Would ignoring any new packets after the interceptor is closed be a good fix? @Sean-Der
