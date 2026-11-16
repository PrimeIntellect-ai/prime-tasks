index out of range panic in `Header.MarshalSize()` when `Extension` set but extensions data missing
#### Summary

We received a crash log from a customer:

```
247310:debug [2025-07-08 10:15:48.085 +02:00] panic: runtime error: index out of range [0] with length 0 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247311:debug [2025-07-08 10:15:48.085 +02:00]                                               caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247312:debug [2025-07-08 10:15:48.085 +02:00] goroutine 17077930 [running]:                 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247313:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/rtp.Header.MarshalSize(...)   caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247314:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/rtp@v1.8.18/packet.go:385    caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247315:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/rtp.HeaderAndPacketMarshalSize(0x1ef1dc0?, {0xc002447814?, 0xc0007c9e20?, 0xc21352ca00000073?}) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247316:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/rtp@v1.8.18/packet.go:617 +0xdc caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247317:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/srtp/v3.(*SessionSRTP).writeRTP(0xc0015a4240, 0xc0011a45a0, {0xc002447814, 0x0, 0x5c8}) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247318:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/srtp/v3@v3.0.5/session_srtp.go:154 +0x134 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247319:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/srtp/v3.(*WriteStreamSRTP).WriteRTP(...) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247320:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/srtp/v3@v3.0.5/stream_srtp.go:147 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247321:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/webrtc/v4.(*srtpWriterFuture).WriteRTP(0x0?, 0xc002822690?, {0xc002447814?, 0x4109c5?, 0x30?}) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247322:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/webrtc/v4@v4.0.7/srtp_writer_future.go:121 +0x6c caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247323:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/webrtc/v4.(*RTPSender).Send.func2(0xc001b72678?, {0xc002447814?, 0x0?, 0xc001dbcde0?}, 0xc002822690?) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247324:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/webrtc/v4@v4.0.7/rtpsender.go:351 +0x2b caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247325:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/interceptor.RTPWriterFunc.Write(0x40f470?, 0xc001cd6380?, {0xc002447814?, 0xc001cd6380?, 0xc001b726c8?}, 0x45bfc5?) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247326:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/interceptor@v0.1.37/interceptor.go:86 +0x2b caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247327:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/interceptor/pkg/nack.(*ResponderInterceptor).resendPackets.func1(0x3d66) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247328:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/interceptor@v0.1.37/pkg/nack/responder_interceptor.go:150 +0x10b caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247329:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/rtcp.(*NackPair).Range(0xc000807ca8, 0xc00129ff98) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247330:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/rtcp@v1.2.15/transport_layer_nack.go:65 +0x29 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247331:debug [2025-07-08 10:15:48.085 +02:00] github.com/pion/interceptor/pkg/nack.(*ResponderInterceptor).resendPackets(0xc0020515c0, 0xc001c05540) caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247332:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/interceptor@v0.1.37/pkg/nack/responder_interceptor.go:145 +0xdb caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247333:debug [2025-07-08 10:15:48.085 +02:00] created by github.com/pion/interceptor/pkg/nack.(*ResponderInterceptor).BindRTCPReader.func1 in goroutine 15268572 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
247334:debug [2025-07-08 10:15:48.085 +02:00] 	github.com/pion/interceptor@v0.1.37/pkg/nack/responder_interceptor.go:92 +0x136 caller="plugin/hclog_adapter.go:54" plugin_id=com.mattermost.calls
```

Looks like we are effectively trusting the input in `rtp.Header.MarshalSize()` so that if `header.Extension` is set, we [assume](https://github.com/pion/rtp/blob/62819f50793022d47d15c500c2b7c6d7b75ff3db/packet.go#L385) `header.Extensions` has at least one element.

Minimal reproducer -> https://go.dev/play/p/qjJjewioADW

```go
package main

import (
	"fmt"

	"github.com/pion/rtp"
)

func main() {
	hdr := &rtp.Header{
		Extension: true,
	}

	fmt.Printf("marshal size is %d\n", hdr.MarshalSize())
}
```

/cc @JoeTurki in case you have thoughts on this one.
