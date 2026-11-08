can't parse poorly-indented chained match expressions without braces
Scala 3.3.1-RC1

`.scalafmt.conf`
```
version = 3.7.10
runner.dialect = Scala3
indent.significant = 2
```

```scala
object small:
  val value =
    Nil match
    case Nil => "empty"
    case _   => "nonempty"
  match
    case "empty"    => 0
    case "nonempty" => 1

```

The code is compilable but scala fmt fails with error:
`Scalafmt parse error (small.scala:95): [dialect scala3] ; expected but match found`
