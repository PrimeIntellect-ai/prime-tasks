Syntax function does not return the correct value for Ifs with an inner if without an else
Using:
  - Scalameta version 4.7.7
  - Scala 2.13.10

Steps to reproduce:
```scala
import scala.meta._

val expr1 = q"if (someCondition1) println(123)"
val expr2 = q"if (someCondition2) ($expr1) else println(321)"

println(expr2.syntax) // this is incorrect
```

actual:
```scala
if (someCondition2) if (someCondition1) println(123) else println(321)
```

expected:
```scala
if (someCondition2) (if (someCondition1) println(123)) else println(321)

OR

if (someCondition2) if (someCondition1) println(123) else () else println(321)
```

---

The `.syntax` is changing the semantics of the expression which shouldn't happen.
