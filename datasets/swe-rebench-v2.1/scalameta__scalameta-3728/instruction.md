False error when splicing a polymorphic function
### Describe the bug

Metals detects an error for this Scala 3 valid code

```scala
def foo(fn: Expr[[A] => A => Unit])(using Quotes) =
  '{${fn}[Int](0)}
//       ^
// Error: `;` expected but `[` found
```

### Expected behavior

No error

### Operating system

Windows

### Editor/Extension

VS Code

### Version of Metals

1.3.1+58-be9ad2e0-SNAPSHOT

### Extra context or search terms

Scala version: 3.4.1
