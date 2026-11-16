Passing a nil channel to GRPC.Stub function errors on compressor
**Describe the bug**
If you pass nil to a GRPC.Stub function rather than a channel as expected, it will fail on `lib/grpc/stub:251: key :compressor not found in: nil`

**To Reproduce**
Steps to reproduce the behavior:
Call any RPC stub function with a nil channel as the first argument

**Expected behavior**
It should give a nice error message or a match error for the appropriate type, rather than an inadvertent error
