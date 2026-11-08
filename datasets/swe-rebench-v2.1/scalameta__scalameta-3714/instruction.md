Parser fails when multiline and one condition wrapped in parenthesis
I was trying to fix it, but it touches whitespace issues which I am not super confident about:
```

  test("issue-metals") {
    runTestAssert(
      """|
         |for (m <- decls
         |    if oneCond
         |      && (cond)
         |      && satisfiable) {}
         |
         |""".stripMargin,
      Some("for (m <- decls; if oneCond && cond && satisfiable) {}")
    )(Term.For(
      List(
        Enumerator.Generator(Pat.Var(Term.Name("m")), Term.Name("decls")),
        Enumerator.Guard(Term.ApplyInfix(
          Term.ApplyInfix(
            Term.Name("oneCond"),
            Term.Name("&&"),
            Type.ArgClause(Nil),
            Term.ArgClause(List(Term.Name("cond")), None)
          ),
          Term.Name("&&"),
          Type.ArgClause(Nil),
          Term.ArgClause(List(Term.Name("satisfiable")), None)
        ))
      ),
      Term.Block(Nil)
    ))
  }
```
