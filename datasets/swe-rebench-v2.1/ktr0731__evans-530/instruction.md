Custom message is not shown on status details
## Describe the bug
When a gRPC server returns error with own custom message in status details, evans doesn't display the message even with --enrich option.
If the message type is ptype (e.g google.protobuf.Timestamp), is it shown. Message types built in the evans binary could be handled.

It happens with both giving proto files or using reflection.
I've confirmed the custom message is provided as details using another tool https://github.com/fullstorydev/grpcurl.

## To reproduce
Here is a Dockerfile to reproduce it: https://github.com/terashi58/grpc-details-test

```
$ git clone https://github.com/terashi58/grpc-details-test.git
$ cd grpc-details-test
$ Docker build . -t grpc-details-test
$ docker run --rm -it grpc-details-test
docker:# tmux
docker:tmux0:# ./bin/server
2022/04/08 16:51:53 server listening at [::]:50051

[Ctrl-b c]
docker:tmux1:# echo '{"name":"gopher","error_message":"fail"}' | evans --proto ./src/proto/hello.proto cli call --enrich Say
content-type: application/grpc

code: Internal
number: 13
message: "error with details"
details:
  {"@type": "type.googleapis.com/google.protobuf.Timestamp", "value": "2022-04-08T16:52:41.277665562Z"}

evans: code = Internal, number = 13, message = "error with details"
```

Summary of the sample codes:

Here is the proto definition:
```hello.proto
package sample;

service Hello {
  rpc Say(SayRequest) returns (SayResponse) {}
}

message Extension {
  string message = 1;
}

message SayRequest {
  string name = 1;
  string error_message = 2;
}

message SayResponse {
  string greet = 1;
}
```

And the RPC implementation:

```.go
func (s *server) Say(ctx context.Context, in *pb.SayRequest) (*pb.SayResponse, error) {
	log.Printf("Received: %v", in.GetName())
	if msg := in.GetErrorMessage(); msg != "" {
		st := status.New(codes.Internal, "error with details")
		st2, err := st.WithDetails(
			&pb.Extension{Message: msg},
			ptypes.TimestampNow(),
		)
		if err != nil {
			return nil, err
		}
		return nil, st2.Err()
	}
	return &pb.SayResponse{Greet: "Hello " + in.GetName()}, nil
}
```

The rpc returns error with the `custom sample.Extension` and `google.protobuf.Timestamp` as status details.
evans shows the Timestamp only in the details section.

## Expected behavior
The custom message is also shown in the details section:

```
docker:tmux1:# echo '{"name":"gopher","error_message":"fail"}' | evans --proto ./src/proto/hello.proto cli call --enrich Say
content-type: application/grpc

code: Internal
number: 13
message: "error with details"
details:
  {"@type": "type.googleapis.com/sample.Extension", "message": "fail"}
  {"@type": "type.googleapis.com/google.protobuf.Timestamp", "value": "2022-04-08T16:52:41.277665562Z"}

evans: code = Internal, number = 13, message = "error with details"
```

## Environment
- OS: Ubuntu 20.04 + debian:bullseye docker image
- Terminal: iTerm2 + tmux (in docker)
- Evans version: 0.10.4
- `protoc` version: 3.20.0
- `protoc` plugin version (if you are using):
  - protoc-gen-go: 1.28.0
  - protoc-gen-go-grpc: 1.2.0

## Additional context
<!-- Add any other context about the problem here. -->
You can run the sample server in the docker image by `docker run -p 50051:50051 --rm grpc-details-test ./bin/server` and test from a local evans.
