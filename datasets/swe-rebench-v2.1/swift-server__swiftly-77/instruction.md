Ensure swiftly can parse tags from apple/swift repository
swiftly currently can parse toolchain selectors of the form `a.b-DEVELOPMENT-SNAPSHOT-YYYY-mm-dd-a`, but tags at https://github.com/apple/swift/tags have a `swift-` prefix, which swiftly cannot parse. We should update the parsing to accept that so that users can easily install a toolchain based on a git tag.

### Additional contract requirements

- Also accept these `swift-`-prefixed release snapshot selectors: `swift-5.7-snapshot`, `swift-5.7-SNAPSHOT`, `swift-5.7-DEVELOPMENT-SNAPSHOT`, `swift-5.7-SNAPSHOT-2023-06-05`, `swift-5.7-DEVELOPMENT-SNAPSHOT-2023-06-05`, and `swift-5.7-DEVELOPMENT-SNAPSHOT-2023-06-05-a`.
