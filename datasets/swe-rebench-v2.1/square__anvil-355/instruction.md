[Dagger factories] Type parameters are not allowed for objects
I've the code, and try to generate dagger's factories with Anvil on modules without components:
```kotlin
interface BaseModel

class NewsModel: BaseModel

class FeedModel: BaseModel

class HtmlToRawMapper<T : BaseModel> @Inject constructor(): ObservableTransformer<List<T>, List<T>> {
    override fun apply(upstream: Observable<List<T>>): ObservableSource<List<T>> =
upstream.flatMapIterable { it }.toList().toObservable()
}

-----
interface Repository

class FeedListRepository: Repository

class NewsListRepository: Repository

-----
@Module
object NewsModule {

    @Provide
    fun provideNewsRepository(
        mapper: HtmlToRawMapper<NewsModel>
    ): Repository = NewsListRepository(mapper)

}

@Module
object FeedModule {

    @Provide
    fun provideFeedRepository(
        mapper: HtmlToRawMapper<FeedModel>
    ): Repository = FeedListRepository(mapper)
}
```

and build failed with:
```
e: /domain/build/anvil/src-gen-release/domain/repository/base/HtmlToRawMapper_Factory.kt: (12, 55): Type parameters are not allowed for objects
e: /domain/build/anvil/src-gen-release/domain/repository/base/HtmlToRawMapper_Factory.kt: (17, 90): Type mismatch: inferred type is HtmlToRawMapper_Factory<T#2 (type parameter of domain.repository.base.HtmlToRawMapper_Factory)> but HtmlToRawMapper_Factory<T#1 (type parameter of domain.repository.base.HtmlToRawMapper_Factory.create)> was expected
```

as result Anvil generate:
```kotlin
public object HtmlToRawMapper_Factory<T : BaseModel> :
    Factory<HtmlToRawMapper<T>> {
  public override fun `get`(): HtmlToRawMapper<T> = newInstance()

  @JvmStatic
  public fun <T : BaseModel> create(): HtmlToRawMapper_Factory<T> = this

  @JvmStatic
  public fun <T : BaseModel> newInstance(): HtmlToRawMapper<T> =
      HtmlToRawMapper<T>()
}
```

but if I add a fake constructor dependency:
```kotlin
class HtmlToRawMapper<T : BaseModel> @Inject constructor(
    private val fakeDeps: Context
): ObservableTransformer<List<T>, List<T>> {
    override fun apply(upstream: Observable<List<T>>): ObservableSource<List<T>> =
upstream.flatMapIterable { it }.toList().toObservable()
}
```
it become compiling fine.
