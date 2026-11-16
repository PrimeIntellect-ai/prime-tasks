Deterministic JSON serialization for `map` types
## Problem

It's not currently possible to deterministically produce JSON data for types that include Protobuf `map` fields since the keys in those maps are not sorted. For example:

```swift
for _ in 0..<10 {
    var message = Some_Message.with { message in
        message.other = [
            "aaa": "abc",
            "111": "abc",
            "eee": "baz",
            "bbb": "baz",
            "ccc": "baz",
            "ddd": "baz",
        ]
    }
    message.other["0new"] = "abc"
    print(String(data: try message.jsonUTF8Data(), encoding: .utf8)!)
}
```

Outputs:

```
{"other":{"ddd":"baz","ccc":"baz","eee":"baz","111":"abc","0new":"abc","aaa":"abc","bbb":"baz"}}
{"other":{"111":"abc","bbb":"baz","ddd":"baz","0new":"abc","aaa":"abc","ccc":"baz","eee":"baz"}}
{"other":{"ddd":"baz","ccc":"baz","eee":"baz","111":"abc","0new":"abc","aaa":"abc","bbb":"baz"}}
{"other":{"111":"abc","bbb":"baz","ddd":"baz","0new":"abc","aaa":"abc","ccc":"baz","eee":"baz"}}
{"other":{"ddd":"baz","ccc":"baz","eee":"baz","111":"abc","0new":"abc","aaa":"abc","bbb":"baz"}}
{"other":{"111":"abc","bbb":"baz","ddd":"baz","0new":"abc","aaa":"abc","ccc":"baz","eee":"baz"}}
{"other":{"ddd":"baz","ccc":"baz","eee":"baz","111":"abc","0new":"abc","aaa":"abc","bbb":"baz"}}
{"other":{"111":"abc","bbb":"baz","ddd":"baz","0new":"abc","aaa":"abc","ccc":"baz","eee":"baz"}}
{"other":{"ddd":"baz","ccc":"baz","eee":"baz","111":"abc","0new":"abc","aaa":"abc","bbb":"baz"}}
{"other":{"111":"abc","bbb":"baz","ddd":"baz","0new":"abc","aaa":"abc","ccc":"baz","eee":"baz"}}
```

## Use case

When sending [Connect Unary GET requests](https://connectrpc.com/docs/protocol#unary-get-request), the serialized payload passed in the URL's query parameters must be deterministic in order to properly enable effective caching. Related: https://github.com/connectrpc/connect-swift/issues/196

## Proposal

Add a `useDeterministicOrdering: Bool = false` field to `JSONEncodingOptions` (similar to what [Protobuf for Go has](https://pkg.go.dev/github.com/golang/protobuf/proto#Buffer.SetDeterministic)) [HIDDEN]

### Additional contract requirements

- `JSONEncodingOptions.useDeterministicOrdering` is a readable and writable `Bool` property. Reading it returns the value most recently assigned, and its default value is `false`.
- When `useDeterministicOrdering` is `true`, JSON serialization emits map entries in ascending key order, so repeated serialization of the same map produces the same entry order.
