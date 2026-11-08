Version 11.x regression: tuple comparison with `==`
- [x] I have read [CONTRIBUTING](https://github.com/Quick/Nimble/blob/main/CONTRIBUTING.md) and have done my best to follow them.

### What did you do?

```swift
expect(tuple) == (a, b)
```

### What did you expect to happen?

This used to compile with Nimble 10.0.0

### What actually happened instead?

> Type '(a: A, b: B)' cannot conform to 'Equatable'

### Environment

List the software versions you're using:

- Quick: 6.0.0
- Nimble: 11.1.0
- Xcode Version: 14.1.0
- Swift Version: 5.7.1

- Carthage: 0.38.0

### Additional contract requirements

The `expect(tuple) == tuple` shorthand performs an equality assertion for tuples with equatable elements. It is available for the tuple arities supported by Nimble's tuple equality matcher, for both synchronous and asynchronous expectations. Unequal tuple values produce a failed assertion; the wording of its diagnostic is not prescribed.
