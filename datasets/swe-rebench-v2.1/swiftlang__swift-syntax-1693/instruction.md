`ArrayExprSyntax` initializer that takes an array of `ExprSyntax`
### Description

Constructing an `ArrayExprSyntax` from a Swift array of arbitrary `ExprSyntax` values is a bit of a pain. Right now, we do silly dances like:

```swift
let exprs: [ExprSyntax] = ...
let exprString = exprs.lazy
  .map(\.trimmedDescription)
  .joined(separator: ", ")
return ExprSyntax("[\(raw: exprString)]").as(ArrayExprSyntax.self)
```

Having a convenience initializer that inserts commas and necessary trailing trivia would make this much nicer.

### Additional contract requirements

- `ArrayExprSyntax` has an initializer with the argument label `expressions:` that takes an array of `ExprSyntax` values. The resulting array literal contains those expressions as its elements, in the given order.
- Consecutive elements of the resulting literal are separated by commas.
- Passing an empty array produces an empty array literal `[]`.
- Expressions that carry trailing whitespace or line breaks still produce a literal that parses without errors and keeps every element.
