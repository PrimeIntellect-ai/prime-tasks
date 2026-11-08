shadow: panic occurs when updating state after get
### Steps to Reproduce
```go
data := map[string]interface{}{
	"foo": "var",
}
err := s.Delete(ctx)
doc, err := s.Report(ctx, data)
doc, err = s.Get(ctx)
doc, err = s.Desire(ctx, data)
```
then panic occurs with the following stack trace.

```
panic: assignment to entry in nil map

goroutine 16 [running]:
github.com/seqsense/aws-iot-device-sdk-go/v5/shadow.updateState(0x0, 0xc00046eae0, 0x10, 0x1ada660)
        /Users/shinichi/workspace/aws-iot-device-sdk-go/shadow/state.go:195 +0x26c
github.com/seqsense/aws-iot-device-sdk-go/v5/shadow.updateStateRaw(0x0, 0xc0000c2040, 0xd, 0x10, 0x0, 0xc00071a000)
        /Users/shinichi/workspace/aws-iot-device-sdk-go/shadow/state.go:159 +0x113
github.com/seqsense/aws-iot-device-sdk-go/v5/shadow.(*ThingDocument).update(0xc0005320a0, 0xc0003fc750, 0xa0, 0x1a644e0)
        /Users/shinichi/workspace/aws-iot-device-sdk-go/shadow/state.go:111 +0x71
github.com/seqsense/aws-iot-device-sdk-go/v5/shadow.(*shadow).updateAccepted(0xc000148af0, 0xc00046ea80)
        /Users/shinichi/workspace/aws-iot-device-sdk-go/shadow/shadow.go:134 +0xc5
github.com/at-wat/mqtt-go.HandlerFunc.Serve(0xc0006987a0, 0xc00046ea80)
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/mqtt.go:68 +0x30
github.com/at-wat/mqtt-go.(*ServeMux).Serve(0xc000148af0, 0xc00046e9c0)
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/servemux.go:50 +0x267
github.com/at-wat/mqtt-go.(*ServeMux).Serve(0xc00049c0d0, 0xc00046e870)
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/servemux.go:50 +0x267
github.com/at-wat/mqtt-go.(*BaseClient).serve(0xc0001c9d90, 0x0, 0xc00051e000)
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/serve.go:85 +0xbf9
github.com/at-wat/mqtt-go.(*BaseClient).Connect.func1(0xc0001c9d90)
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/connect.go:121 +0x2f
created by github.com/at-wat/mqtt-go.(*BaseClient).Connect
        /Users/shinichi/go/pkg/mod/github.com/at-wat/mqtt-go@v0.12.1/connect.go:120 +0x193
```

### Your Environment
- v5.0.0-rc2
- macOS 10.15.7
- Go 1.16
