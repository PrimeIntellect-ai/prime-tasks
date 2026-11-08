`test` and `testIn` do not behave consistently
I've noticed that if a `Flow` is canceled "externally" (e.g. a `StateFlow` that is canceled only when the `CoroutineScope` it was launched in is canceled) then `test` and `testIn` do not behave the same.

While `test` reports all unconsumed events and fails the test, `testIn` does not and passes the test.

```kt
private val flow = flow {
  emit(1)
  emit(2)
  awaitCancellation()
}

// Throws
//   app.cash.turbine.TurbineAssertionError: Unconsumed events found:
//    - Item(2)
@Test
fun test() = runTest {
  flow.test {
    assertEquals(1, awaitItem())
  }
}

// Passes
@Test
fun testIn() = runTest {
  turbineScope {
    val turbine = flow.testIn(backgroundScope)
    assertEquals(1, turbine.awaitItem())
  }
}
```

This is not necessarily caused by the `backgroundScope` as it can be replicated with a custom `CoroutineScope()` + `scope.cancel()` or even when canceling the `Job` the turbine was launched in.

I've figured out this behavior is caused by not handling `CancellationException` as a special case. From the docs of `CancellationException`: "_It indicates normal cancellation of a coroutine_".
