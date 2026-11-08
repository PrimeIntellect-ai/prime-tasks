AssistedFactory mis-detects nullability of function parameters
Anvil turns the lambda's into a `FunctionX` which breaks the assisted injection Factory generation in 2.4.0.
```
e: ItemMarkFoundControllerImpl_FactoryImpl_Impl.kt: (25, 8): Class 'ItemMarkFoundControllerImpl_FactoryImpl_Impl' is not abstract and does not implement abstract member public abstract fun create(upcScanListener: ((String?, String?) -> Unit)?): ItemMarkFoundControllerImpl defined in utils.ItemMarkFoundControllerImpl.FactoryImpl
e: ItemMarkFoundControllerImpl_FactoryImpl_Impl.kt: (28, 10): 'create' overrides nothing
```

Can reproduce with:

```
interface MyApi {
  interface Factory {
    fun create(callback: ((String?, String?) -> Unit)?): MyApi
  }

}

class MyApiImpl @AssistedInjection constructor(@Assisted callback: ((String?, String?) -> Unit)?) {
  @AssistedFactory @ContributesBinding(AppScope::class)
  interface FactoryImpl : Factory {
    override fun create(callback: ((String?, String?) -> Unit)?): MyApiImpl
  }
}
```

I haven't tried with non-nullable types, but looking at the error, just seems like its because the Factory_Impl converts: `((String?, String?) -> Unit)?` into `Function2<String?, String?, Unit>`.


### Update

Played around some more, it's the nullability not being detected. Changing to `(String?, String?) -> Unit` works.

Looks like `((String?, String? -> Unit)?` should be converted to `Function2<String?, String?, Unit>?`
