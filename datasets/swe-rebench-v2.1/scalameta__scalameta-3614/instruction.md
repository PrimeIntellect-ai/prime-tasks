support SIP 53 in parser
https://docs.scala-lang.org/sips/quote-pattern-type-variable-syntax.html

i.e. some code like this
```scala
import scala.quoted.*

def toTuple(list: List[Type[?]])(using Quotes): Type[?] = list match
  case '[t] :: ts => toTuple(ts) match
    case '[type ts <: Tuple; ts] => Type.of[t *: ts]
  case _ => Type.of[EmptyTuple]
```

im trying this out in 3.4.0 which compiles, but metals complains with `identifier expected but type found (scalameta)`
