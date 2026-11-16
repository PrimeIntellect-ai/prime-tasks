PrettyPrinter bug when a Template self has a type but is anonymous
Using:
  - Scalameta version 4.7.7
  - Scala 2.13.10

Steps to reproduce:
```scala
import scala.meta._

val block =
  q"""{
    trait Bar { val b: Int }
    class Foo { _: Bar => def a: Int = b * b }
    println(new Foo with Bar { val b = 10 }.a)
  }"""

block.syntax
```
---

actual:
```scala
{
  trait Bar { val b: Int }
  class Foo { : Bar => def a: Int = b * b }
  println(new Foo with Bar { val b = 10 }.a)
}
```
(Notice the missing `_` in the self of the class `Foo`)

---

expected (same as original):
```scala
{
  trait Bar { val b: Int }
  class Foo { _: Bar => def a: Int = b * b }
  println(new Foo with Bar { val b = 10 }.a)
}
```
