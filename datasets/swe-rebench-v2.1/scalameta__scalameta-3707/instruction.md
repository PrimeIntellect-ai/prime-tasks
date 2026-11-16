ScalametaParser: pos for trailing comments on multi-line expression inconsistent from one dialect to another
```scala
import scala.meta._

val program =
"""
object Main extends App {
  val a = 1 // comment attached to Defn.Val on all dialects
  val b =
    1 // comment attached to Defn.Val on Scala 3 dialect only
}
"""

{
  println("Scala213")
  implicit val scala213: Dialect = dialects.Scala213
  println(program.parse[Stat].get.collect { case v: Defn.Val => v }.map(_.pos))
  println()
}

{
  println("Scala3")
  implicit val scala3: Dialect = dialects.Scala3
  println(program.parse[Stat].get.collect { case v: Defn.Val => v }.map(_.pos))
  println()
}
```

```diff
---Scala213
+++Scala3
 List([29..38) in Input.String("
 object Main extends App {
   val a = 1 // comment attached to Defn.Val on all dialects
   val b =
     1 // comment attached to Defn.Val on Scala 3 dialect only
 }
-"), [89..102) in Input.String("
+"), [89..158) in Input.String("
 object Main extends App {
   val a = 1 // comment attached to Defn.Val on all dialects
   val b =
     1 // comment attached to Defn.Val on Scala 3 dialect only
 }
 "))
```

This makes cross-dialect usage of `AssociatedComments` hard.

I don't have any opinion on what is the right behavior. FWIW,
- the behavior for the Scala213 dialect hasn't changed since at least 4.2.0
- the behavior for the Scala3 dialect hasn't changed since [4.4.33](https://github.com/scalameta/scalameta/releases/tag/v4.4.33) (before that, Scala3 had the same behavior as Scala213)

I found this inconsistency while trying to port a Scala2 Scalafix test to Scala3. I am not aware of any reported problem in production, so "won't fix" is definitely a reasonable outcome for this issue.

### Additional contract requirements

- For the Scala 3 dialect, positions of multi-line expressions must exclude trailing line comments: a `Defn.Val` ending in `1 // comment` has a position ending at `1`, and a `Case` in a multi-line `match` ends at its case-body expression (for example, `(baz, qux)`), not at its trailing `// c1` or `// c2` comment.
