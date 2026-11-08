otelgrpc: server stats handler sets all errors to error=true
### Description

Any server gRPC error codes are treated with `error=true`,  according to [gRPC status spec](https://opentelemetry.io/docs/specs/semconv/rpc/grpc/#grpc-status) only certain server gRPC status codes should set `error=true`.

In the interceptor we check the serverStatus with https://github.com/open-telemetry/opentelemetry-go-contrib/blob/ba19074a6785b2b65c86a52c0649cf040319fa96/instrumentation/google.golang.org/grpc/otelgrpc/interceptor.go#L328-L330 (correct behavior)

[HIDDEN]: https://github.com/open-telemetry/opentelemetry-go-contrib/blob/ba19074a6785b2b65c86a52c0649cf040319fa96/instrumentation/google.golang.org/grpc/otelgrpc/stats_handler.go#L187-L189 (incorrect behavior)

[HIDDEN]

### Environment

- OS: macOS
- Architecture: [e.g. x86, i386]
- Go Version: 1.21
- `otelgrpc` version: v0.46.1

### Steps To Reproduce

1. Write a grpc endpoint that returns `PERMISSION_DENIED`
2. Use `grpc.NewServer(grpc.StatsHandler(otelgrpc.NewServerHandler()))`
3. Call grpc endpoint
4. Trace has error set to true
resulting to this (from stdout)
```
"Status": {
	"Code": "Error",
	"Description": "PERMISSION_DENIED"
},
```

### Expected behavior

If I switch to using `grpc.NewServer(grpc.UnaryInterceptor(otelgrpc.UnaryServerInterceptor()))`
I get the expected behavior:
```
"Status": {
	"Code": "Unset",
	"Description": ""
},
```

### Additional contract requirements

For server spans produced by the gRPC stats handler (`otelgrpc.NewServerHandler`), the span status must follow the gRPC server-status semantics. The span status code is set to `Error` only for the following gRPC status codes, and the span status description is set to the gRPC status message:

- `Unknown`
- `DeadlineExceeded`
- `Unimplemented`
- `Internal`
- `Unavailable`
- `DataLoss`

For every other gRPC status code (including `OK`, `Canceled`, `InvalidArgument`, `NotFound`, `AlreadyExists`, `PermissionDenied`, `ResourceExhausted`, `FailedPrecondition`, `Aborted`, `OutOfRange`, and `Unauthenticated`), the span status code must remain `Unset` with an empty description.
