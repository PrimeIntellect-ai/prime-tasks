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

- In the Scala 3 position cases with indented `if cond then ... else ...` expressions and trailing branch comments, the affected nodes must be reported as `Term.Block` where shown (including branch bodies such as `fx` and `gx`), rather than as `Term.Name`.
- For Scala 3, for `val b =\n    1\n    // comment`, `Defn.Val`'s position must extend through `// comment`, and the initializer must be reported as `Term.Block` with position text `1\n    // comment`.
