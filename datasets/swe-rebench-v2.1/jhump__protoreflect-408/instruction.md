Parser can't recognize custom option for oneof
File `foo.proto`:
```proto
syntax = "proto3";

package foo;

import "google/protobuf/descriptor.proto";

extend google.protobuf.OneofOptions {
  bool my_option = 101400;
}

message MyMessage {
  oneof my_one_of {
    option (my_option) = true;
    int64 my_value = 1;
  }
}
```

Using of `ParseFiles`:
```go
fds, err := protoparse.Parser{}.ParseFiles("foo.proto")
```

After this call `err` contains message:
```
*descriptorpb.OneofDescriptorProto foo.MyMessage.my_one_of: option (my_option): unrecognized extension my_option of google.protobuf.OneofOptions.
```
