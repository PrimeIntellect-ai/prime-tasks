protoparse: Comments dropped if a leading period is used in the field type.
I got a bizarre bug report (googleapis/api-linter#407) this morning:

```proto
import "google/protobuf/timestamp.proto";

message Foo {
  // This is a comment.
  google.protobuf.Timestamp create_time = 1;

  // This is also a comment.
  .google.protobuf.Timestamp update_time = 2;
}
```

The first comment is preserved, the second one is lost. Removing the leading period fixes the issue. I was able to independently verify this in my own testing, also.
