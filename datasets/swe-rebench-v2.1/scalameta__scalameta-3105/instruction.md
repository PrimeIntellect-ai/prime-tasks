Scalameta parsers more than three `???` in line as ApplyInfix
Related https://github.com/scalameta/metals/pull/4877

From scalameta 4.7.2, Scala3 dialect parses the following program as


```scala
def foo =
  ???
  ???
  ???
```

```scala
Defn.Def(
  Nil,
  Term.Name("foo"),
  Nil,
  None,
  Term.ApplyInfix(
    Term.Name("???"),
    Term.Name("???"),
    Type.ArgClause(Nil),
    Term.ArgClause(List(Term.Name("???")), None)
  )
)
```

but it should be

```scala
Defn.Def(
  Nil,
  Term.Name("foo"),
  Nil,
  None,
  Term.Block(List(
    Term.Name("???"),
    Term.Name("???"),
    Term.Name("???")
  ))
)
```


```scala
scala> import scala.meta._
import scala.meta._

scala> val program = """
     | def foo =
     |   ???
     |   ???
     |   ???
     | """
val program: String =
"
def foo =
  ???
  ???
  ???
"

scala> dialects.Scala3(program).parse[Source].get.structure
val res9: String = Source(List(Defn.Def(Nil, Term.Name("foo"), Nil, None, Term.ApplyInfix(Term.Name("???"), Term.Name("???"), Type.ArgClause(Nil), Term.ArgClause(List(Term.Name("???")), None)))))
```

---

Interestingly,

```scala
def foo =
  x
  x
  x
```

will be parsed as

```scala
Defn.Def(
  Nil,
  Term.Name("foo"),
  Nil,
  None,
  Term.Block(List(
    Term.Name("x"),
    Term.Name("x"),
    Term.Name("x")
  ))
)
```

### Additional contract requirements

- Additionally, under the Scala 3 dialect, parsing this input must fail with the exact diagnostic shown:

```scala
{
  println("hello")
    ???
    }
}
```

```text
error: Invalid indented leading infix operator found
    ???
    ^
```
