generateDaggerFactories sometimes creates kotlin.Lazy instead of dagger.Lazy
Kotlin 1.4.30
Anvil 2.1.0

reproducer: https://github.com/RBusarow/AnvilFactoriesLazy

Given this code:

``` Kotlin
class OkHttpClient @Inject constructor()

class Retrofit(private val client: OkHttpClient)

@Module
@ContributesTo(AppScope::class)
object RetrofitModule {

  @Provides
  fun provideRetrofit(
    lazyClient: dagger.Lazy<OkHttpClient>
  ): Retrofit = Retrofit(lazyClient.get())
}
```

Compilation fails with this error message:
```
/lib/build/anvil/src-gen-main/com/reproducer/RetrofitModule_ProvideRetrofitFactory.kt: (26, 67): Type mismatch: inferred type is kotlin.Lazy<OkHttpClient> but dagger.Lazy<OkHttpClient> was expected
```

And the generated factory is:
``` Kotlin
package com.reproducer

import dagger.`internal`.Factory
import dagger.`internal`.Preconditions
import javax.inject.Provider
import kotlin.Lazy
import kotlin.Suppress
import kotlin.jvm.JvmStatic

public class RetrofitModule_ProvideRetrofitFactory(
  private val param0: Provider<Lazy<OkHttpClient>>
) : Factory<Retrofit> {
  public override fun `get`(): Retrofit = provideRetrofit(param0.get())

  public companion object {
    @JvmStatic
    public fun create(param0: Provider<Lazy<OkHttpClient>>): RetrofitModule_ProvideRetrofitFactory =
        RetrofitModule_ProvideRetrofitFactory(param0)

    @JvmStatic
    public fun provideRetrofit(param0: Lazy<OkHttpClient>): Retrofit =
        Preconditions.checkNotNull(RetrofitModule.provideRetrofit(param0),
        "Cannot return null from a non-@Nullable @Provides method")
  }
}
```

This only happens if the function parameter is the qualified `dagger.Lazy<T>`.

All these alternatives work fine:
- `import dagger.Lazy` with a function parameter of `Lazy<Foo>`
- `import dagger.Lazy as DaggerLazy` with a function parameter of `DaggerLazy<Foo>`
- `typalias DaggerLazy<T> = dagger.Lazy<T>` with a function parameter of `DaggerLazy<Foo>`
