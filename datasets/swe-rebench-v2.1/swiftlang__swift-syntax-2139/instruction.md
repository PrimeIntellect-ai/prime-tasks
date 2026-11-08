Diagnostic triggered for every multi-binding variable declaration
### Description

The `MacroApplicationError.accessorMacroOnVariableWithMultipleBindings` diagnostic error is leaking into all nested variable declarations that have multiple bindings.

For quick reference, here's the invalid usage that merits the error:

```
@constantOneGetter
var x: Int, y: Int
┬─────────────────
╰─ 🛑 swift-syntax applies macros syntactically and there is no way to represent a variable
      declaration with multiple bindings that have accessors syntactically. While the compiler
      allows this expansion, swift-syntax cannot represent it and thus disallows it.
```

Here are two cases where the error is erroneously triggered:

```
@Test
struct S {
  var x: Int, y: Int
  ┬─────────────────
  ╰─ 🛑 swift-syntax … no way to represent a variable declaration with multiple bindings…
}

@Test
struct Q {
  struct R {
    var i: Int, j: Int
    ┬─────────────────
    ╰─ 🛑 swift-syntax … no way to represent a variable declaration with multiple bindings…
  }
}
```

### Steps to Reproduce

Add these two two failing tests to `MemberMacroTests` (failing on `main`, I tested 71b7378):

```swift
// ...

  func testStructVariableDeclWithMultipleBindings() {
    struct TestMacro: MemberMacro {
      static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
      ) throws -> [DeclSyntax] {
        return []
      }
    }

    assertMacroExpansion(
      """
      @Test
      struct S {
        var x: Int, y: Int
      }
      """,
      expandedSource: """
      struct S {
        var x: Int, y: Int
      }
      """,
      macros: ["Test": TestMacro.self],
      indentationWidth: indentationWidth
    )
  }

  func testNestedStructVariableDeclWithMultipleBindings() {
    struct TestMacro: MemberMacro {
      static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
      ) throws -> [DeclSyntax] {
        return []
      }
    }

    assertMacroExpansion(
      """
      @Test
      struct Q {
        struct R {
          var i: Int, j: Int
        }
      }
      """,
      expandedSource: """
      struct Q {
        struct R {
          var i: Int, j: Int
        }
      }
      """,
      macros: ["Test": TestMacro.self],
      indentationWidth: indentationWidth
    )
  }

// ...
```
