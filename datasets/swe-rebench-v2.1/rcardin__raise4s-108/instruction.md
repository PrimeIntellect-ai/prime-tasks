Add a `combineErrorsS` function for `Iterable[Raise[Error] ?=> A]` type that uses a `Semigroup[Error]` instance
Add a `combineErrorsS` function for `Iterable[Raise[Error] ?=> A]` type that uses a `Semigroup[Error]` instance. The function must behave like the following:

```scala 3
import cats.Semigroup

implicit val intAdditionSemigroup: Semigroup[String] = _ + _

val intermediateResults: List[Raise[String] ?=> Int] = List(1, 2, 3, 4).map(i => raise(i.toString))
val results: Raise[String] ?=> List[Int] = intermediateResults.combineErrorsS
```
