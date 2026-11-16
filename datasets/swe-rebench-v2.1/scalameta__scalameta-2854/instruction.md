Type alias definition using 'with' keyword show error message, but can be run successfully.
### Describe the bug

```
type A = AnyRef with
  type T>: Null
```
The above is accepted by Scala 3.2.0/3.1.3 REPL:
```
scala> type A = AnyRef with
     |   type T>: Null
     |
// defined alias type A = AnyRef{T >: Null}
```

But in VS Code, there is a red indicator under the 'with' keyword, and the problem panel display "identifier expected but indent found scalameta". Even so, I can successfully launch the code in VS Code that contain the above definition.


### Expected behavior

It should not display the error message.

### Operating system

Linux

### Editor/Extension

VS Code

### Version of Metals

v1.19.0

### Extra context or search terms

_No response_

### Additional contract requirements

- For `type A = Product with\n  type T>: Null\n with\n    type D <: Product`, report exactly `error: ; expected but with found`. For `type AA = String with Int with\n    type T>: Null\n{\n  type T>: Int\n}`, report exactly `; expected but { found`.
