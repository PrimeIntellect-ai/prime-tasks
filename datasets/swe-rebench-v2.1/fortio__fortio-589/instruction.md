return non 0 status (shell error) for grpcping -health
fortio curl already returns 0 for 200 and 1 for non 200, let's do the same for grpc health SERVING

### Additional contract requirements

For `grpcping -health`, the process exits with status 0 when the requested health status is SERVING and with a nonzero status when it is not SERVING.
