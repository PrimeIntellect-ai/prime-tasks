Unintended unchunking when using Monad instance of Stream
When using implementations of cats' type classes instances `fs2.Stream#monadErrorInstance` or `fs2.StreamLowPriority#monadInstance` unchunking will occur as a side effect.

```scala
def testCase(pipe: Pipe[fs2.Pure, Int, (Int, Int)]) = (Stream(1,2,3) ++ Stream(4,5,6)) .through(pipe).chunks.toList

testCase(_.map(e => e -> (e + 1)))
// List(Chunk((1,2), (2,3), (3,4)), Chunk((4,5), (5,6), (6,7)))

testCase(_.fproduct(_ + 1))
// List(Chunk((1,2)), Chunk((2,3)), Chunk((3,4)), Chunk((4,5)), Chunk((5,6)), Chunk((6,7)))
```

This happens because the default implementation of `map` in `Monad` is [HIDDEN]. [HIDDEN] I think such unchunking may decrease the performance. By a lot?

### Additional contract requirements

- Applying `map` through either the `StreamLowPriority` `Monad` instance or the `Stream` `MonadError` instance transforms every element and preserves the source stream's chunk boundaries and their order.
