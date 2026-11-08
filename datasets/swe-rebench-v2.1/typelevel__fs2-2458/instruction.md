Regression in fs2 2.5.7 produces ArrayIndexOutOfBoundsException using writeOutputStream and readOutputStream
This code properly works ok fs2 2.5.6:

```scala
import $ivy.`co.fs2::fs2-core:2.5.6`
import $ivy.`co.fs2::fs2-io:2.5.6`

import cats.effect._
import fs2._

val blocker = Blocker[IO].allocated.unsafeRunSync._1
implicit val CS = IO.contextShift(scala.concurrent.ExecutionContext.global)

val DefaultChunkSize: Int = 16

def test[F[_]: ConcurrentEffect: ContextShift](blocker: Blocker): Pipe[F, Byte, Byte] = source => {
  fs2.io.readOutputStream(blocker, DefaultChunkSize)(os =>
    source.through(fs2.io.writeOutputStream(Sync[F].delay(os), blocker, true)).compile.drain
  )
}

val source: fs2.Stream[IO, Byte] = fs2.Stream.range(0,10).map(_.toByte).repeat.take(DefaultChunkSize * 2).buffer(15)

source.through(test(blocker)).through(fs2.text.utf8Decode).compile.foldMonoid.unsafeRunSync
```

But it fails with `ArrayIndexOutOfBoundsException` on fs2 2.5.7:
```scala
import $ivy.`co.fs2::fs2-core:2.5.7`
import $ivy.`co.fs2::fs2-io:2.5.7`

import cats.effect._
import fs2._

val blocker = Blocker[IO].allocated.unsafeRunSync._1
implicit val CS = IO.contextShift(scala.concurrent.ExecutionContext.global)

val DefaultChunkSize: Int = 16

def test[F[_]: ConcurrentEffect: ContextShift](blocker: Blocker): Pipe[F, Byte, Byte] = source => {
  fs2.io.readOutputStream(blocker, DefaultChunkSize)(os =>
    source.through(fs2.io.writeOutputStream(Sync[F].delay(os), blocker, true)).compile.drain
  )
}

val source: fs2.Stream[IO, Byte] = fs2.Stream.range(0,10).map(_.toByte).repeat.take(DefaultChunkSize * 2).buffer(15)

source.through(test(blocker)).through(fs2.text.utf8Decode).compile.foldMonoid.unsafeRunSync
```

Returning:
```
java.lang.ArrayIndexOutOfBoundsException
  java.lang.System.arraycopy(Native Method)
  fs2.io.internal.PipedStreamBuffer$$anon$2.write(PipedStreamBuffer.scala:273)
  java.io.OutputStream.write(OutputStream.java:75)
  fs2.io.package$.$anonfun$writeOutputStream$3(io.scala:136)
  unsafeRunSync @ ammonite.$sess.cmd4$.<clinit>(cmd4.sc:1)
  delay$extension @ fs2.io.package$.$anonfun$readOutputStream$2(io.scala:165)
  map @ fs2.internal.CompileScope.interruptibleEval(CompileScope.scala:413)
  flatMap @ fs2.internal.FreeC$.go$1(Algebra.scala:503)
  flatMap @ fs2.internal.FreeC$.interruptGuard$1(Algebra.scala:436)
```

It seems there is some problem with the size of the chunks of the source stream (15) not being a multiple of the `readOutputStream` given chunk size for reading (16).
