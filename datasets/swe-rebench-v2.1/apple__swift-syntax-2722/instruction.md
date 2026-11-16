Accessor Macros applied to properties with trailing trivia comments lead to Swift that fails to compile.
### Description

The following Swift code fails to compile:

```swift
var x: Int // comment {
  get {
    return 1
  }
}
```

The trailing trivia comment captures the opening round brace… which leads to the compiler error.

We can attach an accessor macro to a variable declaration with similar trailing trivia:

```swift
@constantOne
var x: Int // comment
```

Which expands to:

```swift
var x: Int // comment {
  get {
    return 1
  }
}
```

Maybe we should do something about that comment trivia… could we place the comment trivia after (to the right of) the opening curly brace?

```swift
var x: Int { // comment
  get {
    return 1
  }
}
```

Could we enclose the trailing trivia with asterisks?

```swift
var x: Int /* comment */ {
  get {
    return 1
  }
}
```

### Steps to Reproduce

Here is a diff on `swift-syntax` to repro:

```
diff --git a/Tests/SwiftSyntaxMacroExpansionTest/AccessorMacroTests.swift b/Tests/SwiftSyntaxMacroExpansionTest/AccessorMacroTests.swift
index 471a34c7..97e2b8bc 100644
--- a/Tests/SwiftSyntaxMacroExpansionTest/AccessorMacroTests.swift
+++ b/Tests/SwiftSyntaxMacroExpansionTest/AccessorMacroTests.swift
@@ -43,6 +43,24 @@ fileprivate struct ConstantOneGetter: AccessorMacro {

 final class AccessorMacroTests: XCTestCase {
   private let indentationWidth: Trivia = .spaces(2)
+
+  func testAccessorWithComment() {
+    assertMacroExpansion(
+      """
+      @constantOne
+      var x: Int // comment
+      """,
+      expandedSource: """
+        var x: Int {
+          get {
+            return 1
+          }
+        }
+        """,
+      macros: ["constantOne": ConstantOneGetter.self],
+      indentationWidth: indentationWidth
+    )
+  }

   func testAccessorOnVariableDeclWithExistingGetter() {
     assertMacroExpansion(

```

### Additional contract requirements

- When an accessor macro adds an accessor block to a variable declaration with trailing comment trivia and no existing accessor block, preserve that trivia immediately after the opening brace. For example, `var x: Int // comment` must expand with `var x: Int { // comment`, and `var x: Int /// hello` must expand with `var x: Int { /// hello`.
- The expansion shown in the reproduction that places `{` after `// comment` is not the required behavior; the comment must instead follow the opening brace.
