Incorrect PacketsReceived value from RemoteInboundRTPStreamStats
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  We also provide a Knowledge Base https://pion.ly/knowledge-base that covers Pion and general WebRTC

  We maintain a FAQ of common issues and questions https://pion.ly/knowledge-base/pion-basics/faq/

 Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: v0.1.17

### What did you do?
<!--
If possible, provide an example for reproducing the error.
A complete runnable program is good.
-->
Captured `OutboundRTPStreamStats` and `RemoteInboundRTPStreamStats` using the stats interceptor, from a previously defined track.

```go
go func() {
	var stats *stats.Stats

	ssrc := uint32(rtpSender.GetParameters().Encodings[0].SSRC)
	for !element.stop {
		stats = statsGetter.Get(ssrc)
		if stats != nil {
			log.Println(stats.OutboundRTPStreamStats, stats.RemoteInboundRTPStreamStats)
		}
		time.Sleep(time.Second * 5)
	}
}()
```

### What did you expect?
Values of `PacketsSent` from `OutboundRTPStreamStats` should be aligned or slightly higher than `PacketsReceived` from `RemoteInboundRTPStreamStats`.

### What happened?
Once in a while, `PacketsReceived`'s value explode and is not correctly aligned anymore:

```
2023/06/26 14:31:19 OutboundRTPStreamStats
        PacketsSent: 2991
        BytesSent: 3501804
        HeaderBytesSent: 35892
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 2991
        PacketsLost: 0
        Jitter: 0.0192
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0

2023/06/26 14:31:24 OutboundRTPStreamStats
        PacketsSent: 3588
        BytesSent: 4196307
        HeaderBytesSent: 43056
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 3583
        PacketsLost: 0
        Jitter: 0.017822222222222222
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0

2023/06/26 14:31:29 OutboundRTPStreamStats
        PacketsSent: 4185
        BytesSent: 4893407
        HeaderBytesSent: 50220
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 4185
        PacketsLost: 0
        Jitter: 0.021566666666666668
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0

2023/06/26 14:31:34 OutboundRTPStreamStats
        PacketsSent: 4785
        BytesSent: 5595347
        HeaderBytesSent: 57420
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 4294841009
        PacketsLost: 0
        Jitter: 0.022344444444444445
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0

2023/06/26 14:31:39 OutboundRTPStreamStats
        PacketsSent: 5384
        BytesSent: 6300016
        HeaderBytesSent: 64608
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 4294841608
        PacketsLost: 0
        Jitter: 0.0145
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0

2023/06/26 14:31:44 OutboundRTPStreamStats
        PacketsSent: 6115
        BytesSent: 7160160
        HeaderBytesSent: 73380
        NACKCount: 0
        FIRCount: 0
        PLICount: 0
 RemoteInboundRTPStreamStats:
        PacketsReceived: 4294842339
        PacketsLost: 0
        Jitter: 0.011177777777777778
        RoundTripTime: 0s
        TotalRoundTripTime: 0s
        FractionLost: 0
        RoundTripTimeMeasurements: 0
```
