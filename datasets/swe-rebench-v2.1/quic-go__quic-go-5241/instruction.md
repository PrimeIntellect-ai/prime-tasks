flaky TestPathManagerOutgoingRetransmissions
```
 === RUN   TestPathManagerOutgoingRetransmissions
    path_manager_outgoing_test.go:170:
        	Error Trace:	D:/a/quic-go/quic-go/path_manager_outgoing_test.go:170
        	Error:      	"473.9836ms" is not less than "450ms"
        	Test:       	TestPathManagerOutgoingRetransmissions
--- FAIL: TestPathManagerOutgoingRetransmissions (0.47s)

### Additional contract requirements

- For the first four outgoing `PATH_CHALLENGE` transmissions from a probe, let `i` be the zero-based index of a transmission after the first. The interval since the preceding transmission must be greater than `initialRTT << (i-1)` and less than `initialRTT << i`.
