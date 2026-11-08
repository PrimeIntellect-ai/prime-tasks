SE-0367 unimplemented
### Issue Kind

Parse of Valid Source Failed

### Source Code

```swift
#if hasAttribute(foo)
@foo
#endif
struct MyStruct {}
```

### Description

This will currently produce a `expected declaration after attribute in conditional compilation clause` diagnostic, but since SE-0367 this is now valid code. See https://github.com/apple/swift/pull/60208 and https://github.com/apple/swift/pull/60720. The test cases in `DirectiveTests` will also need to be updated.
