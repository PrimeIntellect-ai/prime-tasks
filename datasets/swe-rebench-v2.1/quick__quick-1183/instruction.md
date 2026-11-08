MainActor is ignored when using `fit`
- [x] I have read [CONTRIBUTING](https://github.com/Quick/Quick/blob/main/CONTRIBUTING.md) and have done my best to follow them.

### What did you do?

When using `fit`, the `@MainActor` attribute is "ignored".

```swift
@MainActor
final class Thread_Spec: QuickSpec {
    override func spec() {
        describe("isMainThread") {
            fit("should be true") {
                expect(Thread.isMainThread) == true // fails
            }
        }
    }
}
```

OR

```swift
final class Thread_Spec: QuickSpec {
    override func spec() {
        describe("isMainThread") {
            fit("should be true") { @MainActor in
                expect(Thread.isMainThread) == true // fails
            }
        }
    }
}
```

### What did you expect to happen?

`Thread.isMainThread` should return `true`.

### What actually happened instead?

`Thread.isMainThread` returns `false`.

### Environment

List the software versions you're using:

 - Quick: v6.0.0
 - Nimble: v11.1.0
 - Xcode Version: 14.1
 - Swift Version: 5.7.1

Please also mention which package manager you used and its version. Delete the
other package managers in this list:

 - Carthage: 0.38.0
