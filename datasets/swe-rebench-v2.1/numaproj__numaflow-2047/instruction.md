eventTimeExtractor to support keys
# Summary

I found that the [Event Time Extractor Spec](https://numaflow.numaproj.io/user-guide/sources/transformer/builtin-transformers/event-time-extractor/#event-time-extractor-spec) ignores the keys when reading from a Kafka source. Guess the relevant code is [here](https://github.com/numaproj/numaflow/blob/2189ea9ec23368a9fdebaa72667b85c0fe9c4fc2/pkg/sources/transformer/builtin/event_time/event_time_extractor.go#L59C27-L59C39).

Proposing to use the source keys (for example Kafka keys) and set them in the output messages.

# Use Cases

Generally speaking eventTimeExtractor doesn't work with keyed sources.

Actually, we don't key our Kafka streams. But the above can still lead to buggy behaviour.
I have two Kafka topics where events are produced without keys. Kafka appears to represent no keys with an empty string "" by default (at least in our setup).
1. The first topic is read by eventTimeExtractor. The output has `keys=[]` (should be `[""]`)
2. The second topic is read by a custom `sourcetransformer`. Keys are passed through in the `handler`. The output is `keys=[""]`.
3. The downstreams vertices (mapper) incorrectly handles the two sources as separate keyed-streams, so the won't be joined in reducer vertices.

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you wish to see this enhancement implemented please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.
