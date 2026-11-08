Future.finally should run even when the computation is cancelled
Since `Future.finally` is a simplified version of `Future.hook` (one where the `cleanup` does not depend on the resource), it would be better if they both behaved the same way under cancellation.

I propose that the `finally`-computation is started and cancelled immediately when the computation is cancelled, similar to how `hook` behaves.
