remove golang.org/x/net/context from all non gRPC packages

### Additional contract requirements

- The requirement applies to every package in the repository except gRPC packages
  (for example, packages under `plugin/grpc` and `examples/grpc`). Both production
  and test files must use the standard library `context` package.
