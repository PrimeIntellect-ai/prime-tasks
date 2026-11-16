After_X_Y_Z stubs prevent round-tripping in quasiquotes
Probably known, but I didn't see an issue for it. Pinning it here for others searching.

During the ABI-preserving migration, forward-compatible `unapply` methods have been into inner objects named `After_X_Y_Z`. [HIDDEN], the following blows up:

```scala
scala> val x = q"""new Foo(a = a, b = b)"""
x: meta.Term.New = new Foo(a = a, b = b)

scala> val q"""new Foo(a = a, b = b)""" = x

scala> val q"""new Foo(..$params)""" = x
<console>:16: error: exception during macro expansion:
java.lang.UnsupportedOperationException: unsupported unquoting position
        at scala.meta.Term$ArgClause$Quasi$TermArgClauseQuasiImpl.values(Trees.scala:113)
        at scala.meta.Term$ArgClause$Quasi$TermArgClauseQuasiImpl.values(Trees.scala:113)
        at scala.meta.internal.trees.PlaceholderChecks$.$anonfun$hasPlaceholder$2(PlaceholderChecks.scala:41)
        at scala.meta.internal.trees.PlaceholderChecks$.$anonfun$hasPlaceholder$2$adapted(PlaceholderChecks.scala:41)
            ....
        at scala.meta.internal.quasiquotes.ReificationMacros.unapply(ReificationMacros.scala:55)
            ....
        at scala.tools.nsc.typechecker.Macros.macroExpandWithRuntime(Macros.scala:849)

       val q"""new Foo(..$params)""" = x
           ^
```

Rolling back to scalameta 4.5.13 shows the expected behavior:

```
@ val q"""new Foo(..${params})""" = x
params: List[Term] = List(Term.Assign(Term.Name("a"), Term.Name("a")), Term.Assign(Term.Name("b"), Term.Name("b")))
```

### Additional contract requirements

- Matching `q"""new Foo(...$params)"""` against `term = q"""new Foo(a = a, b = b)"""` must succeed and capture `List(Term.ArgClause(List(Term.Assign(Term.Name("a"), Term.Name("a")), Term.Assign(Term.Name("b"), Term.Name("b"))), None))`.
- Matching `q"""new Foo(..$params)"""` against `new Foo(a = a, b = b)` must succeed and capture the two assignment terms as a `List[Term]`.
