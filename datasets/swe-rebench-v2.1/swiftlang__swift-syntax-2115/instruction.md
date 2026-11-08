`assertMacroExpansion` reports duplicate diagnostic
### Description

Expression macros that throw errors report duplicate diagnostics to `assertMacroExpansion`, and these duplicate diagnostics must be asserted against.

### Steps to Reproduce

I have a slightly modified version of the default template `#stringify` macro that throws an error when the input is too long:

```diff
 public struct StringifyMacro: ExpressionMacro {
   public static func expansion<
     F: FreestandingMacroExpansionSyntax, C: MacroExpansionContext
   >(
     of node: F,
     in context: C
-  ) -> ExprSyntax {
+  ) throws -> ExprSyntax {
     guard let argument = node.argumentList.first?.expression else {
       fatalError("compiler bug: the macro does not have any arguments")
     }

+    guard argument.description.count <= 20
+    else {
+      throw SomeError()
+    }
+
     return "(\(argument), \(literal: argument.description))"
   }
 }
+
+struct SomeError: Error {}
```

If I write an expansion test for this:

```swift
assertMacroExpansion(
  """
  #stringify(a + b + c + d + e + f)
  """,
  expandedSource: """
    #stringify(a + b + c + d + e + f)
    """,
  macros: testMacros
)
```

I get the following failure:

> 🛑 failed - Expected 0 diagnostics but received 2:
> 1:1: SomeError()
> 1:1: SomeError()

Updating the assertion requires including _two_ diagnostics even though there should be just one.
