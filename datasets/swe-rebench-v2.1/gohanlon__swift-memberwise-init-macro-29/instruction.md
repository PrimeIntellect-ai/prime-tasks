Crash when given invalid redeclaration
### Description

The following invalid Swift will cause MemberwiseInit to crash with a fatal error:

```swift
@MemberwiseInit
struct S {
  let x: Int
  let x: Int
}
```

This will also crash: `let x, x: Int`.

### Checklist

- [X] If possible, I've reproduced the issue using the `main` branch of this package.
- [X] This issue hasn't been addressed in an [existing GitHub issue](https://github.com/gohanlon/swift-memberwise-init-macro/issues) or [discussion](https://github.com/gohanlon/swift-memberwise-init-macro/discussions).

### Expected behavior

MemberwiseInit should never crash. It should either emit invalid Swift code or fail silently.

### swift-memberwise-init-macro version information

main, as of db35b64.

### Additional contract requirements

- For the duplicate-name forms shown in the issue, `@MemberwiseInit` must not crash; it may emit invalid Swift code or fail silently.
- When `@Init(label: "x") let x: T` and another `let x: T` occur in the same `@MemberwiseInit` struct, emit the diagnostic `Label 'x' conflicts with a property name`.
