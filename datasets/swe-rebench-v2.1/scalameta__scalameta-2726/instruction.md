InvariantFailedException when printing a type with a literal type parameter
`Foo[42]` can be parsed but can't be printed.

```scala
@ import $ivy.`org.scalameta::scalameta:4.5.3`, scala.meta._
import $ivy.$                               , scala.meta._

@ t"Foo[42]"
res1: Type.Apply = Type.Apply(tpe = Type.Name(value = "Foo"), args = List(Lit.Int(value = 42)))

@ res1.syntax
org.scalameta.invariants.InvariantFailedException: invariant failed:
[HIDDEN]
  org.scalameta.invariants.InvariantFailedException$.raise(Exceptions.scala:19)
  [HIDDEN]
  scala.meta.internal.prettyprinters.TreeSyntax$SyntaxInstances.p(TreeSyntax.scala:115)
  scala.meta.internal.prettyprinters.TreeSyntax$SyntaxInstances.$anonfun$syntaxTree$35(TreeSyntax.scala:620)
  scala.collection.immutable.List.map(List.scala:246)
  scala.meta.internal.prettyprinters.TreeSyntax$SyntaxInstances.$anonfun$syntaxTree$1(TreeSyntax.scala:620)
  scala.meta.prettyprinters.Syntax$$anon$1.apply(Syntax.scala:9)
  scala.meta.internal.prettyprinters.TreeSyntax$.reprint(TreeSyntax.scala:1228)
  scala.meta.internal.prettyprinters.TreeSyntax$.$anonfun$apply$1(TreeSyntax.scala:1222)
  scala.meta.prettyprinters.Syntax$$anon$1.apply(Syntax.scala:9)
  scala.meta.prettyprinters.Api$XtensionSyntax.syntax(Api.scala:11)
  ammonite.$sess.cmd2$.<clinit>(cmd2.sc:1)
```

### Additional contract requirements

- Printing a type application with a literal type argument must succeed and retain the literal argument in the emitted source syntax; for example, printing the parsed `Foo[42]` must emit `Foo[42]`.
