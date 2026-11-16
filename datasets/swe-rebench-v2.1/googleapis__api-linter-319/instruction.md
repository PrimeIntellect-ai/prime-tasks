api-linter only prints first build error
Given the following file:

```proto
syntax = "proto3";

package foo;

message One {
  // First build error, no semicolon.
  int64 one = 1
}

message Two {
  // Second build error, no semicolon.
  int64 two = 2
}

```

The following is outputted from `protoc`, `buf`, and `api-linter`:

```
$ protoc -o /dev/null foo.proto
foo.proto:8:1: Expected ";".
foo.proto:13:1: Expected ";".

# also buf image build -o /dev/null
$ buf check lint
foo.proto:8:1:syntax error: unexpected '}', expecting ';' or '['
foo.proto:13:1:syntax error: unexpected '}', expecting ';' or '['

$ api-linter foo.proto
2019/11/07 12:16:45 foo.proto:8:1: syntax error: unexpected '}', expecting ';' or '['
```

The issue is that api-linter is not using https://godoc.org/github.com/jhump/protoreflect/desc/protoparse#ErrorReporter. This means that if a file has multiple build errors, they will only be reported one at a time, which can lead to only fixing single issues at a time and a lot of back-and-forth with editing your files.

It would also be nice if these issues were not printed as log statements, and the messages did not have the prefix " " after the column if possible, but this may not be something that `api-linter` wants to do.
