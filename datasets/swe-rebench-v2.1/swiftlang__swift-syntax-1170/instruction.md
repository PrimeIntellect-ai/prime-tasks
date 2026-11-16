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

- Add a public initializer `IfStmt.init(_ signature: String, @CodeBlockItemListBuilder bodyBuilder: () -> CodeBlockItemList, @CodeBlockItemListBuilder else elseBuilder: () -> CodeBlockItemList? = { nil })` in module `SwiftSyntaxBuilder`. `signature` is a raw `if ...` string (for example `"if foo == x"`). The initializer builds an `IfStmt` whose body contains the statements produced by `bodyBuilder`. When `elseBuilder` produces statements, the result has an `else` branch containing those statements. When `elseBuilder` is omitted or produces no statements (returns `nil`), the result has no `else` branch.
- Add a public initializer `IfStmt.init(_ signature: String, @CodeBlockItemListBuilder bodyBuilder: () -> CodeBlockItemList, elseIf: IfStmt)` in module `SwiftSyntaxBuilder`. The initializer builds an `IfStmt` whose body contains the statements produced by `bodyBuilder` and which has an `else if` branch equal to the given `elseIf` statement.
- When serialized, an `else` or `else if` branch follows the preceding closing brace with no intervening whitespace: `}else {`.
