Improvement for`IfStmt` in SyntaxBuilder
### Description

When creating an `IfStmt` it would be more convenient to write

```swift
IfStmt("if [.init, .as].contains(token.tokenKind), let nextTokenKind = token.nextToken(viewMode: .sourceAccurate)?.tokenKind") {
}
```

instead of


```swift
IfStmt(
  conditions: ConditionElementList {
    OptionalBindingCondition(
      letOrVarKeyword: .let,
      pattern: PatternSyntax("nextTokenKind"),
      initializer: InitializerClause(value: Expr("token.nextToken(viewMode: .sourceAccurate)?.tokenKind"))
    )
  }
)
```

### Additional contract requirements

- Add a public initializer `IfStmt.init(_ signature: String, @CodeBlockItemListBuilder bodyBuilder: () -> CodeBlockItemList, @CodeBlockItemListBuilder else elseBuilder: () -> CodeBlockItemList? = { nil })` in module `SwiftSyntaxBuilder`. The `signature` is the raw `if …` header (for example `"if foo == x"`); `bodyBuilder` produces the statements of the `if` body. When `elseBuilder` returns `nil`, no `else` clause is emitted; otherwise its statements form the `else` body.
- Add a public initializer `IfStmt.init(_ signature: String, @CodeBlockItemListBuilder bodyBuilder: () -> CodeBlockItemList, elseIf: IfStmt)` in module `SwiftSyntaxBuilder`. It builds the primary `if` clause from `signature` and `bodyBuilder` and attaches the supplied `IfStmt` as the subsequent `else if` branch. The supplied `elseIf` may itself contain further `elseIf` or `else` branches.
- When printed, an `else` branch has no space between the preceding `}` and `else` (`}else {`), and an `elseIf` branch is printed as `}else if`.


- - When printed, statements in `if` and `else` bodies are indented by four spaces.
