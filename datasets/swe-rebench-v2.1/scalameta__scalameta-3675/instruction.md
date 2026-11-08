return `Type.AnonymousParam(None)` if type name endsWith `*`
`Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String("type A = ***")
    val p = implicitly[parsers.Parse[Stat]]
    println(p.apply(src, dialects.Scala3).get.structure)
  }
}
```

`build.sbt`

```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.9.3"

scalaVersion := "2.13.13"
```

scalameta 4.9.3 and 4.9.2

```scala
Defn.Type(Nil, Type.Name("A"), Type.ParamClause(Nil), Type.AnonymousParam(None), Type.Bounds(None, None))
```

scalameta 4.9.1

```scala
Defn.Type(Nil, Type.Name("A"), Type.ParamClause(Nil), Type.Name("***"), Type.Bounds(None, None))
```

### Additional contract requirements

The trailing-`*` rule applies only to the exact anonymous type-parameter
placeholders `*`, `+*` and `-*`:

- `*` parses to `Type.AnonymousParam(None)`.
- `+*` parses to `Type.AnonymousParam(Some(Mod.Covariant()))`.
- `-*` parses to `Type.AnonymousParam(Some(Mod.Contravariant()))`.

A longer type name that merely ends with `*`, such as `***`, is not an
anonymous type parameter: it parses to a plain type name, i.e.
`Type.Name("***")`.
