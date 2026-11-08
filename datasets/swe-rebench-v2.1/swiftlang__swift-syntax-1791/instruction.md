Extraneous indentation if the formatted node has parents
The following new test case fails

```swift
let decl: DeclSyntax = """
  func test() {
    print(1)
  }
"""

let body = decl.cast(FunctionDeclSyntax.self).body!

let expectedFormatted = """
  {
      print(1)
    }
  """

assertStringsEqualWithDiff(body.formatted().description, expectedFormatted) // fails: `print` is indented by 8 spaces
assertStringsEqualWithDiff(body.detach().formatted().description, expectedFormatted) // passes
```

For some reason we are adding 8 spaces in front of `print` if `body` is not detached.
