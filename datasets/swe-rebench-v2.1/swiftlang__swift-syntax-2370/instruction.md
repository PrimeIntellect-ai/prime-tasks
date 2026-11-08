Closure arguments parsed as attribute parameters
### Issue Kind

Parse of Valid Source Produced Invalid Syntax Tree

### Source Code

```swift
f { @Sendable (e: Int) in }
```


### Description

Parsing the code snippet, `swift-parser-cli print-tree` produces the tree

```
SourceFileSyntax
├─statements: CodeBlockItemListSyntax
│ ╰─[0]: CodeBlockItemSyntax
│   ╰─item: FunctionCallExprSyntax
│     ├─calledExpression: DeclReferenceExprSyntax
│     │ ╰─baseName: identifier("f")
│     ├─arguments: LabeledExprListSyntax
│     ├─trailingClosure: ClosureExprSyntax
│     │ ├─leftBrace: leftBrace
│     │ ├─signature: ClosureSignatureSyntax
│     │ │ ├─attributes: AttributeListSyntax
│     │ │ │ ╰─[0]: AttributeSyntax
│     │ │ │   ├─atSign: atSign
│     │ │ │   ├─attributeName: IdentifierTypeSyntax
│     │ │ │   │ ╰─name: identifier("Sendable")
│     │ │ │   ├─leftParen: leftParen
│     │ │ │   ├─arguments: LabeledExprListSyntax
│     │ │ │   │ ╰─[0]: LabeledExprSyntax
│     │ │ │   │   ├─label: identifier("e")
│     │ │ │   │   ├─colon: colon
│     │ │ │   │   ╰─expression: DeclReferenceExprSyntax
│     │ │ │   │     ╰─baseName: identifier("Int")
│     │ │ │   ╰─rightParen: rightParen
│     │ │ ╰─inKeyword: keyword(SwiftSyntax.Keyword.in)
│     │ ├─statements: CodeBlockItemListSyntax
│     │ ╰─rightBrace: rightBrace
│     ╰─additionalTrailingClosures: MultipleTrailingClosureElementListSyntax
╰─endOfFileToken: endOfFile
```

which shows that `(e: Int)` is interpreted as the parameter list of `@Sendable` while it is actually meant to be the argument list for the closure.

Is this an ambiguity only the compiler can resolve with full type information available?
