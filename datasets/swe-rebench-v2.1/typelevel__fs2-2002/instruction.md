Chunk.traverse loses elements in 2.4.3 for chunks larger than 255 elements
The result of this snippet is smaller than it should be:
```scala
import cats._
import cats.implicits._
import fs2._

fs2.Chunk.vector(1.to(256).toVector).traverse(a => a: Id[Int])
```
