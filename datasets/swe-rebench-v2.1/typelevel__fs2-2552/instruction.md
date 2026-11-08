Stream.parJoin freezes using an EitherT as effect context
In my project we use an `EitherT` as effect context instead of directly using an `IO` (it allows better error handling without the need of using a `MonadError` or just throwing up exceptions). We have seen that, in case we would want to parallelize a stream of streams using this type as context, in case an effect evaluates as a left that function gets stuck at `Stream#parJoin` function.

I have written some tests [here](https://github.com/aldtid/fs2-parjoin-error-with-eithert) that can reproduce the error while running streams in parallel and how running the same function sequentially finishes the execution as expected. The interesting test is this one:

https://github.com/aldtid/fs2-parjoin-error-with-eithert/blob/2adc2ea42973405c783a2acd3ba3faa2307ca0ba/src/test/scala/com/example/JoinTest.scala#L49-L62

which is the one that freezes, the rest returns the expected results.
