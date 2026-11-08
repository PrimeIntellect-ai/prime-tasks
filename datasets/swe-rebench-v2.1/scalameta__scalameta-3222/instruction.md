ScalametaParser: missing `(` in postfix
4.6.0 OK
```scala
@ """(10) + 1 toInt""".parse[Stat].get.collect { case Term.Select(qual, _) => qual }.head.syntax
res1: String = "(10) + 1"
```

4.7.0 KO
```scala
@ """(10) + 1 toInt""".parse[Stat].get.collect { case Term.Select(qual, _) => qual }.head.syntax
res1: String = "10) + 1"
```

4.8.0 KO
```scala
@ """(10) + 1 toInt""".parse[Stat].get.collect { case Term.Select(qual, _) => qual }.head.syntax
res1: String = "10) + 1"
```

Originally reported in https://github.com/scalacenter/scalafix/issues/1794
