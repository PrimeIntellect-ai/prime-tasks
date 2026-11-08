Parser should emit a single diagnostic if both open and close quote are missing from string literal
### Issue Kind

Bad Diagnostic Produced

### Source Code

```swift
@_expose(Cxx, baz) func foo() {}
```


### Description

From https://github.com/apple/swift-syntax/pull/1688/files#r1201105564

In the above example the parser produces two diagnostics: One for the missing opening `"` before `baz` and one for the missing closing `"` after `baz`. It should emit a single diagnostic instead that offers to add both.

### Additional contract requirements

- The diagnostic message must be `expected code '<code>' to be surrounded by '"'`, where `<code>` is the string content. Its fix-it label must be `insert '"' and '"'`.
- The diagnostic is reported at the first character of the string content.
