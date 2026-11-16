spec v1, pubsub transport: couldn't make it work, errs
I used this example as base:

https://github.com/cloudevents/sdk-go/tree/master/cmd/samples/pubsub

Using PubSub Transport, everything worked fine when used v03.

When trying to use v1, just changing `cloudevents.VersionV03` for `cloudevents.VersionV1` in:

https://github.com/cloudevents/sdk-go/blob/master/cmd/samples/pubsub/sender/main.go#L45

Throws this error on a loop:

```
{"level":"error","ts":1573823257.217474,"logger":"fallback","caller":"pubsub/transport.go:241","msg":"failed to decode message","error":"unknown encoding: Unknown Encoding","stacktrace":"github.com/cloudevents/sdk-go/pkg/cloudevents/transport/pubsub.(*Transport).startSubscriber.func1\n\t/Users/lopezator/go/pkg/mod/github.com/cloudevents/sdk-go@v0.10.0/pkg/cloudevents/transport/pubsub/transport.go:241\ngithub.com/cloudevents/sdk-go/pkg/cloudevents/transport/pubsub/internal.(*Connection).Receive.func1\n\t/Users/lopezator/go/pkg/mod/github.com/cloudevents/sdk-go@v0.10.0/pkg/cloudevents/transport/pubsub/internal/connection.go:187\ncloud.google.com/go/pubsub.(*Subscription).receive.func3\n\t/Users/lopezator/go/pkg/mod/cloud.google.com/go@v0.40.0/pubsub/subscription.go:633"}
```

What could I do?

Maybe this also could be a good opportunity to update the examples ans start using v1 on them. I could take over this if you give me any hint.

### Additional contract requirements

- The `pubsub.Codec` type's `Decode` method must decode Pub/Sub messages carrying CloudEvents payloads in both v0.3 and v1.0, returning an event whose context is the matching version.
- The `pubsub.CodecV03` and `pubsub.CodecV1` types must each expose a settable `DefaultEncoding` field of type `pubsub.Encoding`.
