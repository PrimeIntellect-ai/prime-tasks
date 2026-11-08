New parser fails to parse `@convention` attribute with `cType` argument inside an array type
### Issue Kind

Parse of Valid Source Failed

### Source Code

```swift
_ = [@convention(c, cType: "int (*)(int)") (Int32) -> Int32]()
```


### Description

The issue is that the implementation of `skipTypeAttribute` doesn’t skip over the `cType` argument here. [HIDDEN]

https://github.com/apple/swift-syntax/blob/89dd2bde9404950dede113b7898c97f6e2bc2fc4/Sources/SwiftParser/Lookahead.swift#L165-L173

### Additional contract requirements

- The parser must successfully parse the shown valid array type and preserve the `@convention` attribute’s `cType` argument in the parsed syntax.
