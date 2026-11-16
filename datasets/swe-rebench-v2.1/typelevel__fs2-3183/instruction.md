groupWithin: inconsistent behaviour on source termination
### fs2 version 3.6.1
### [scastie](https://scastie.scala-lang.org/HAeMqP3BTXSUBGuf2eqPMg)

While playing around with a new implementation of groupWithin I discovered a bug. The combinator doesn't handle upstream termination consistently. See below

```scala
    val finiteStream = Stream
      .range(0, 4)
      .covary[IO]
      .metered(1.second)

    val doesNotTerminate =
        finiteStream
          .groupWithin(Int.MaxValue, 2.days)
          .evalTap(IO.println)
          .compile
          .lastOrError.void

    val terminates =
         finiteStream
          .groupWithin(8, 2.days)
          .evalTap(IO.println)
          .compile
          .lastOrError.void
```

I have an idea why this is happening. I'm happy to take a look 💪🏾

The question I have though is: what's the correct behaviour here ?
 - terminating the stream when upstream terminates
 - keeping the stream alive

### Additional contract requirements

The correct behaviour is: when the upstream terminates, including when it is
interrupted, `groupWithin` must terminate the downstream immediately, emitting
whatever elements have been accumulated at the time of termination. The stream
must not stay alive waiting for the grouping time window to expire.
