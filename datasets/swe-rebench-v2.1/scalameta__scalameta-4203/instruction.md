New line needed but no way to represent it
When I create a Val that is assigned the yield of a for-yield and then in the same block we also have a Select in a Block for example it will be wrapped in { } which will be perceived by the compiler as an extension of the yield. This means the AST is not bidirectional and when it is parsed back it will just generate one large Val:
A basic example below, when put back into the AST explorer will only show one Val

`  val tree: Term.Block = Term.Block(
    List(
      Defn.Val(
        Nil,
        List(Pat.Var(Term.Name("a"))),
        None,
        Term.ForYield(
          List(
            Enumerator
              .Generator(Pat.Var(Term.Name("i")), Term.ApplyInfix(Lit.Int(1), Term.Name("to"), Nil, List(Lit.Int(10))))
          ),
          Term.Apply(Term.Name("i"), List(Lit.Int(2)))
        )
      ),
      Term.Apply(Term.Select(Term.Block(List(Term.Name("a"))), Term.Name("this")), Nil)
    )
  )`


If we could add a semicolon after yield result or a new line after val it all works fine, but I don't see a way of representing this in the AST. Can you please advise if it is possible and if not can it be implemented?

### Additional contract requirements

- When a newline is needed to separate a preceding statement from a following block-like statement, `TreeSyntax.reprint` must render `"\n"` between them rather than using a semicolon.
