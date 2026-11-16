Named tuples parser error on latest metals snapshot
Metals server version: `1.4.0+6-73dc6db8-SNAPSHOT` which already includes `Scalameta v4.11.0` that added support for named tuples.

Code:
```scala
val y = summon[Tuple2[Int, String] <:< (x: Int, y: String)]
```

Error:
```
`)` expected but `:` found
```
