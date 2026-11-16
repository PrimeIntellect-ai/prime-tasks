Anonymous class without braces in if block with braces fails to parse
Related https://github.com/scalameta/metals/pull/4877

Scalameta >= 4.7.2 fails to parse the following program with Scala3 dialect

```scala
if(x) {
  new TreeMap:
    override def foo = ???
}
```

while the following works

```scala
if(x)
  new TreeMap:
    override def foo = ???
```


```
scala> import scala.meta._
import scala.meta._

scala> val program = """
     | if(x) {
     |   new TreeMap:
     |     def foo = ???
     | }
     | """
val program: String =
"
if(x) {
  new TreeMap:
    def foo = ???
}
"

scala> dialects.Scala3(program).parse[Stat]
val res0: scala.meta.parsers.Parsed[scala.meta.Stat] =
<input>:3: error: expected template body
  new TreeMap:
              ^

```
