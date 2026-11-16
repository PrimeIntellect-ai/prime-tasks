Inconsistency with Scalac on package private fields of case classes
Scala [3.2.2](https://scastie.scala-lang.org/yKRRHRKjStu1EsBnJ0NhKA), [2.13.10](https://scastie.scala-lang.org/KqrtO9P6TcGnZeogV6TmCw), and [2.12.17](https://scastie.scala-lang.org/0g6bJlZ9RfSZvwx9iK4QdQ) at least (and probably every other version support package private fields of case classes without the `val` keyword:

```scala
package example

case class Foo(private[example] field: String)
```

Semantic db prior to 4.7.5 also supported it, but starting in 4.7.5, semanticdb throws exceptions like:
```
[error] failed to generate semanticdb for .../src/main/scala/example/Hello.scala:
[error] .../src/main/scala/example/Hello.scala:4: error: val expected but identifier found
[error]   case class Foo(private[example] field: String)
[error]                                   ^
[error]         at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
[error]         at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:16)
[error]         at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
[error]         at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:17)
[error]         at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:17)
```

I'm guessing this is actually a bug in Scalac, but ideally the behavior of semanticdb would be consistent with that of Scalac.

### Additional contract requirements

- Parsing `case class Foo(private[example] field: String)` with the default Scala dialect must succeed, without a syntax error.
- The resulting tree must be a case class `Foo` whose primary constructor has a single parameter `field` of type `String` that keeps the modifier `private[example]`. The parameter is not declared with `val`, and the parser must not add a `val` modifier to it.
