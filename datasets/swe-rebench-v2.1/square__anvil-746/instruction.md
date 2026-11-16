Suspend lambda parameters are not supported when generating code for AssistedInject/AssistedFactory
With a source file like:

```
data class AssistedService @AssistedInject constructor(
        @Assisted val action: suspend () -> String?
      )
```

We get an error like:

```
    e: Class 'AssistedServiceFactory_Impl' is not abstract and does not implement abstract member public abstract fun create(stringFactory: suspend (Int) -> String): AssistedService defined in com.squareup.test.AssistedServiceFactory
    e: AssistedServiceFactory_Impl.kt:25:3 'create' overrides nothing
```
