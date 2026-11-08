Unexpected trivia when removing attributes in `MacroSystem`
### Description

On `509.0.0` and `main` ([`8966ec7`](https://github.com/apple/swift-syntax/commit/8966ec7157f9774dd3b03b53520e75bc570a284a)), I'm running into the following unexpected trivia handling in a peer macro:

```swift
fileprivate struct NoOpPeerMacro: PeerMacro {
  static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    return []
  }
}

final class PeerMacroTests: XCTestCase {
  // …
  func testEmptyBeforeAttributeOnSameLineAsMemberVariable() {
    assertMacroExpansion(
      """
      struct Foo {
        @Test @State var x: Int
      }
      """,
      expandedSource: """
        struct Foo {
          @State var x: Int
        }
        """,
      macros: ["Test": NoOpPeerMacro.self]
    )
  }
  // …
}
```

Output:
```diff
–struct Foo {
–  @State var x: Int
+struct Foo {@State
+  var x: Int
 }
```

_Quick reference_: [`AttributeRemover`]( https://github.com/apple/swift-syntax/blob/8966ec7157f9774dd3b03b53520e75bc570a284a/Sources/SwiftSyntaxMacroExpansion/MacroSystem.swift#L387C15-L387C31).

To work around, I can tailor the whitespace in my test in a specific manner as follows:

```swift
struct Foo {
  @Test
  @State
  var x: Int
}
```

What is the expected trivia treatment in this case? Should trivia in test cases be deliberately crafted, or should the `MacroSystem` strive to normalize all syntactically valid trivia in some predictable way?

_Aside: Here are a couple other tests and outputs that I found surprising:_

<details>
  <summary>Click to expand!</summary>

```swift
  func testAttributeOnOwnLineThenEmptyBeforeVariable() {
    assertMacroExpansion(
      """
      @State
      @Test var x: Int
      """,
      expandedSource: """
        @State
        var x: Int
        """,
      macros: [
        "Test": NoOpPeerMacro.self
      ]
    )
  }
```

Output:
```diff
–@State
–var x: Int
+@Statevar x: Int
```
---

```swift
  func testEmptyAfterAttributeOnSameLineAsMemberVariable() {
    assertMacroExpansion(
      """
      struct Foo {
        @State @Test var x: Int
      }
      """,
      expandedSource: """
        struct Foo {
          @State var x: Int
        }
        """,
      macros: ["Test": NoOpPeerMacro.self]
    )
  }
```

Output:
```diff
 struct Foo {
–  @State var x: Int
+  @State
+  var x: Int
 }
```

---

```swift
  func testEmptyOnOwnLineThenAttributedMemberVariable() {
    assertMacroExpansion(
      """
      struct Foo {
        @Test
        @State var x: Int
      }
      """,
      expandedSource: """
        struct Foo {
          @State var x: Int
        }
        """,
      macros: ["Test": NoOpPeerMacro.self]
    )
  }
```

Output:
```diff
 struct Foo {
–  @State var x: Int
+  @State
+  var x: Int
 }
```
</details>


### Steps to Reproduce

Add the tests included in the description to "Tests/SwiftMacroExpansionTest/PeerMacroTests.swift" and run them.

### Additional contract requirements

- Given the source ` @Test var value: Int`, removing the empty `@Test` attribute must produce ` var value: Int`, preserving the single leading space.
- When removing `@Test` from `@State \t  @Test \t  var x: Int`, preserve the horizontal trivia so the result is `@State \t  var x: Int` (where `\t` denotes a tab).
- Removing an attribute must not leave behind the horizontal whitespace that separated it from the following attribute or declaration. In particular, removing both attributes from `@Test @Test var x: Int` must produce `var x: Int`.
