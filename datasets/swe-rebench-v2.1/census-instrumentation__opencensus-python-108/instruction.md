OpenCensusServerInterceptor reports incorrect timing
There is a bug in OpenCensusServerInterceptor that causes server spans to be finished immediately. You can reproduce it by running the helloworld grpc example in examples/trace/grpc. You should see a server span with a very short execution time, for example when I run it locally with a print exporter I get:

`{'traceId': 'a8fdeb7813144b178cb4b3d3d9b8fee4', 'spans': [{'childSpanCount': 0, 'displayName': {'truncated_byte_count': 0, 'value': 'grpc_server'}, 'parentSpanId': 4417962580138865, 'startTime': '2018-01-23T16:01:17.826761Z', 'attributes': {'attributeMap': {'/component': {'string_value': {'truncated_byte_count': 0, 'value': 'grpc'}}}}, 'spanId': 7098108131070600, 'endTime': '2018-01-23T16:01:17.826771Z'}]}`

The problem is that [this line](https://github.com/census-instrumentation/opencensus-python/blob/master/opencensus/trace/ext/grpc/server_interceptor.py#L62) is being traced, but it isn't actually executing the server handler code. It just returns an RPCMethodHandler, which defers execution.

[HIDDEN]

Happy to submit a PR if you have a preferred approach. Thanks!

### Additional contract requirements

A server span must remain open while the RPC handler executes and must not be finished until that handler completes. If the handler raises an exception, the exception must propagate to the caller and its message must be recorded on the span as `/error/message`.
