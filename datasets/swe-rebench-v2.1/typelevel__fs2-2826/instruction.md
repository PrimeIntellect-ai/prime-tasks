parEvalMapUnordered and friends can deadlock on exceptions in fs2 3.x, but not in fs2 2.x
The following program gets stuck (deadlocks, never terminates) on fs2 3.2.4, but immediately finishes with an exception on fs2 2.5.10:

```scala
import cats.effect.{IO, IOApp}
import fs2.Stream

object Main extends IOApp.Simple {
  def explodeIf1(int: Int): IO[Unit] = {
    if (int == 1) {
      throw new RuntimeException("kaboom")
      // If using IO.raiseError instead, the program terminates also for fs2 3.x.
      // IO.raiseError(new RuntimeException("kaboom!"))
    } else {
      IO.unit
    }
  }

  override def run: IO[Unit] = {
    println("Hello, world!")

    val nums = 1.to(1).iterator

    Stream
      .fromIterator[IO](nums, chunkSize = 10)
      .parEvalMapUnordered[IO, Unit](2) { i =>
      explodeIf1(i)
    }.compile.drain
  }
}
```
The program also finishes (with an exception) on fs2 3.2.4 if we change `maxConcurrent` to 1, or use `IO.raiseError` instead of `throw`.

I don't think this is expected behavior, and that it should work the same as in fs2 2.x. Although we should ideally not throw, exceptions can not always be avoided.

### Additional contract requirements

- The same behavior is required for `parEvalMap`: if its mapping function throws synchronously, the stream must terminate with an exception rather than hang.
