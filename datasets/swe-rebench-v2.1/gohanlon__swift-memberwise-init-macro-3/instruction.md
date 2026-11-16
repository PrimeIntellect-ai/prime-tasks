Optional `var` properties should default to `nil` for non-public initializers
### Description

MemberwiseInit's behavior doesn't match Swift's memberwise init:

```swift
struct S {
  var v: String?
}
_ = S()

@MemberwiseInit
struct M {
  var v: String?
}
_ = M()  // 🛑 Compiler error: Missing argument for parameter 'v' in call
```

MemberwiseInit provides this initializer:

```swift
internal init(
  v: String
) {
  self.v = v
}
```

but, to match Swift's memberwise init, MemberwiseInit should provide:

```swift
internal init(
  v: String? = nil
) {
  self.v = v
}
```

(Thanks, @AndreiChenchik!)

### Checklist

- [X] If possible, I've reproduced the issue using the `main` branch of this package.
- [X] This issue hasn't been addressed in an [existing GitHub issue](https://github.com/gohanlon/swift-memberwise-init-macro/issues) or [discussion](https://github.com/gohanlon/swift-memberwise-init-macro/discussions).

### swift-memberwise-init-macro version information

0.1.0
