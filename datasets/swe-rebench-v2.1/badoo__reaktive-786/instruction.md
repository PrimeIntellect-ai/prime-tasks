`StackOverflowError` is not reported
## Description

I created the following example:

```kotlin
package dev.oleks

import com.badoo.reaktive.single.flatMap
import com.badoo.reaktive.single.subscribe
import com.badoo.reaktive.single.toSingle


fun main() {
    var mapSingle = emptyMap<Int, String>().toSingle()
    repeat(5000) { index ->
        mapSingle = mapSingle.flatMap { map ->
            (map + (index to index.toString())).toSingle()
        }
    }

    var result: Result<Map<Int, String>>? = null
    mapSingle.subscribe(onSuccess = {
        result = Result.success(it)
    }, onError = {
        result = Result.failure(it)
    })
    checkNotNull(result) { "Neither onSuccess nor onError was called" }
    println(result!!.getOrThrow().size)
}
```

Running it with version 2.3.0 results in the following output:

```
Exception in thread "main" java.lang.IllegalStateException: Neither onSuccess nor onError was called
        at dev.oleks.MainKt.main(Main.kt:22)
        at dev.oleks.MainKt.main(Main.kt)
```


Note, that neither the `onError` was called nor the ["onError callback failed"](https://github.com/badoo/Reaktive/blob/e46d432956c4d09841595b2408b4ba53742d5da8/reaktive/src/commonMain/kotlin/com/badoo/reaktive/utils/HandleSourceError.kt#L25) message was printed.

When setting a breakpoint in error handling code, the following original stack trace can be recovered:

```
java.lang.StackOverflowError
	at com.badoo.reaktive.utils.HandleSourceErrorKt.handleReaktiveError(HandleSourceError.kt:9)
	at com.badoo.reaktive.single.FlatMapKt$flatMap$1$1.onSuccess(FlatMap.kt:52)
	at com.badoo.reaktive.single.SingleByEmitterKt$onSubscribeSingle$1.onSuccess(SingleByEmitter.kt:27)
	at com.badoo.reaktive.single.FlatMapKt$flatMap$1$1$onSuccess$1$1.onSuccess(FlatMap.kt)
	at com.badoo.reaktive.single.VariousKt$singleOf$$inlined$singleUnsafe$1.subscribe(Various.kt:21)
	at com.badoo.reaktive.single.VariousKt$singleOf$$inlined$singleUnsafe$1.subscribe(Various.kt:13)
	at com.badoo.reaktive.single.FlatMapKt$flatMap$1$1.onSuccess(FlatMap.kt:24)
	at com.badoo.reaktive.single.SingleByEmitterKt$onSubscribeSingle$1.onSuccess(SingleByEmitter.kt:27)
	at com.badoo.reaktive.single.FlatMapKt$flatMap$1$1$onSuccess$1$1.onSuccess(FlatMap.kt)
	at com.badoo.reaktive.single.VariousKt$singleOf$$inlined$singleUnsafe$1.subscribe(Various.kt:21)
	at com.badoo.reaktive.single.VariousKt$singleOf$$inlined$singleUnsafe$1.subscribe(Various.kt:13)
	at com.badoo.reaktive.single.FlatMapKt$flatMap$1$1.onSuccess(FlatMap.kt:24)
        ....
```

## Additional information

The issue seems similar to https://github.com/ReactiveX/RxJava/issues/748.

Other JVM implementations of Reactive Extensions rethrow `VirtualMachineError` (e.g, `StackOverflowError`), `ThreadDeath` and `LinkageError`[^1][^2] because they cannot always be recovered from.

[^1]: https://github.com/reactor/reactor-core/blob/7259f57d52aafa7f23d6863962ef790ac18f7095/reactor-core/src/main/java/reactor/core/Exceptions.java#L453
[^2]: https://github.com/ReactiveX/RxJava/blob/5c8ddcba3f40f37a24808c17d2cb26d08c370db7/src/main/java/io/reactivex/rxjava3/exceptions/Exceptions.java#L66
