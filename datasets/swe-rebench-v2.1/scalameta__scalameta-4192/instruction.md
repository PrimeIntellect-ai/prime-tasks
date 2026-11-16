Regression crash when nested fors combined with given and braceless lambda passing
For scalafmt 3.8.6, following code:
```scala
import scala.util.Random
def foo(n: String)(i: Seq[Int]) = i

@main def m =
  given Random(1)
  for _ <- 1 to 10 do
    foo("Hello"):
      for i <- 0 to 10 yield i
```

Causes this error:
```
error: [dialect scala3 [with overrides]] `identifier` expected but `for` found
      for i <- 0 to 10 yield i
      ^
```

Works in scalafmt 3.8.3
