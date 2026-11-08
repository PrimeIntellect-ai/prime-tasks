InvalidPos handling of ARRAY keyword in ArrayLiteral seems wrong
`ARRAY` is always printed in `ArrayLiteral`, even if `ARRAY` keyword is not used.
```
$ go run ./tools/parse --mode expr '[]'
--- AST
&ast.ArrayLiteral{
  Array:  0,
  Lbrack: 0,
  Rbrack: 1,
  Type:   nil,
  Values: []ast.Expr(nil),
}

--- SQL
ARRAY[]
$ go run ./tools/parse --mode expr 'ARRAY[]'
--- AST
&ast.ArrayLiteral{
  Array:  0,
  Lbrack: 5,
  Rbrack: 6,
  Type:   nil,
  Values: []ast.Expr(nil),
}

--- SQL
ARRAY[]
```

I believe it should also be fixed because `Array.Invalid()` is handled

https://github.com/cloudspannerecosystem/memefish/blob/ad392f19203b64436c2a14cf0f079cf949c4f899/ast/pos.go#L418-L421

but [HIDDEN]

### Additional contract requirements

- For an array literal parsed without the `ARRAY` keyword, the AST must represent that keyword position as invalid, and the SQL representation must omit `ARRAY`.
- For an array literal parsed with `ARRAY`, the SQL representation must retain the keyword.
