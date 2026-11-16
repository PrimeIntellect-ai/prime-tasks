where clauses not handled correctly
```kotlin
class SKTokenSelectDelegateImpl<SCDMBinder> @Inject constructor(
  private val prefsManagerLazy: Lazy<PrefsManager>,
  private val slackConnectDmViewBinderLazy: Lazy<SCDMBinder>,
  private val tokenResultsUserViewBinderLazy: Lazy<TokenResultsUserViewBinder>,
  @AndroidIncreaseMpdmLimitFeatureFlag private val increaseMpdmLimit: Boolean,
) : SKTokenSelectDelegate where SCDMBinder : SKListCustomViewBinder, SCDMBinder : SKTokenSlackConnectDmBinder {
```

Generates

```kotlin
public class SKTokenSelectDelegateImpl_Factory<SCDMBinder>(
  private val param0: Provider<@JvmSuppressWildcards PrefsManager>,
  private val param1: Provider<@JvmSuppressWildcards SCDMBinder>,
  private val param2: Provider<@JvmSuppressWildcards TokenResultsUserViewBinder>,
  private val param3: Provider<Boolean>
) : Factory<SKTokenSelectDelegateImpl<SCDMBinder>> {
```

the generated factory is missing the bounds on `SCDMBinder`
