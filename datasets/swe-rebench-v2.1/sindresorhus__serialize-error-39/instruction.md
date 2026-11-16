OutOfMemory exception on errors containing Buffers
I use `serialize-error` as a way to handle all generic errors coming from different tiers service. It works well most of the time, except for Slack.

I use Slack SDK (https://github.com/SlackAPI/node-slack-sdk) to send, well, messages in Slack.
When I try to send a message to an inexistent Channel, an exception is thrown, with a pretty big Error.
It contains an object that is a Buffer. When `serialize-error` try to `stringify` it, I got an error that make the whole server crash.

Is there a way to have a better handling of Buffer ?

The logs:

```
FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory

1: 0x8dc1c0 node::Abort() [/usr/local/bin/node]
 2: 0x8dc20c  [/usr/local/bin/node]
 3: 0xad60ae v8::Utils::ReportOOMFailure(v8::internal::Isolate*, char const*, bool) [/usr/local/bin/node]
 4: 0xad62e4 v8::internal::V8::FatalProcessOutOfMemory(v8::internal::Isolate*, char const*, bool) [/usr/local/bin/node]
 5: 0xec3972  [/usr/local/bin/node]
 6: 0xec3a78 v8::internal::Heap::CheckIneffectiveMarkCompact(unsigned long, double) [/usr/local/bin/node]
 7: 0xecfb52 v8::internal::Heap::PerformGarbageCollection(v8::internal::GarbageCollector, v8::GCCallbackFlags) [/usr/local/bin/node]
 8: 0xed0484 v8::internal::Heap::CollectGarbage(v8::internal::AllocationSpace, v8::internal::GarbageCollectionReason, v8::GCCallbackFlags) [/usr/local/bin/node]
 9: 0xed30f1 v8::internal::Heap::AllocateRawWithRetryOrFail(int, v8::internal::AllocationSpace, v8::internal::AllocationAlignment) [/usr/local/bin/node]
10: 0xe9b3d5  [/usr/local/bin/node]
11: 0xea2c4a v8::internal::Factory::NewRawOneByteString(int, v8::internal::PretenureFlag) [/usr/local/bin/node]
12: 0x11d2845 v8::internal::IncrementalStringBuilder::Extend() [/usr/local/bin/node]
13: 0xf9ce88 v8::internal::JsonStringifier::SerializeArrayLikeSlow(v8::internal::Handle<v8::internal::JSReceiver>, unsigned int, unsigned int) [/usr/local/bin/node]
14: 0xf993f6 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
15: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
16: 0xf9a1e5 v8::internal::JsonStringifier::SerializeJSReceiverSlow(v8::internal::Handle<v8::internal::JSReceiver>) [/usr/local/bin/node]
17: 0xf98e41 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
18: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
19: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
20: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
21: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
22: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
23: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
24: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
25: 0xf9a1e5 v8::internal::JsonStringifier::SerializeJSReceiverSlow(v8::internal::Handle<v8::internal::JSReceiver>) [/usr/local/bin/node]
26: 0xf98e41 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
27: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
28: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
29: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
30: 0xf9c6fd v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<false>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
31: 0xf9cd4e v8::internal::JsonStringifier::SerializeArrayLikeSlow(v8::internal::Handle<v8::internal::JSReceiver>, unsigned int, unsigned int) [/usr/local/bin/node]
32: 0xf993f6 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
33: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
34: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
35: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
36: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
37: 0xf991e1 v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<true>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
38: 0xf9c6fd v8::internal::JsonStringifier::Result v8::internal::JsonStringifier::Serialize_<false>(v8::internal::Handle<v8::internal::Object>, bool, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
39: 0xf9d459 v8::internal::JsonStringifier::Stringify(v8::internal::Handle<v8::internal::Object>, v8::internal::Handle<v8::internal::Object>, v8::internal::Handle<v8::internal::Object>) [/usr/local/bin/node]
40: 0xba4eb1 v8::internal::Builtin_JsonStringify(int, v8::internal::Object**, v8::internal::Isolate*) [/usr/local/bin/node]
41: 0x31ef91bdbf7d
```

### Additional contract requirements

- When serializing an object with a Buffer-valued property, serialize that property as the exact string `[object Buffer]`.
