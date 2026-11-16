`Provider<Lazy<Type>>` not handled properly for member injection
Given this:

```kotlin
class InjectClass {
  @Inject lateinit var lazyStringProvider: Provider<Lazy<String>>
}
```

This is generated:
```kotlin
public class InjectClass_MembersInjector(
  private val param0: Provider<@JvmSuppressWildcards String>
) : MembersInjector<InjectClass> {
  public override fun injectMembers(instance: InjectClass): Unit {
    injectLazyStringProvider(instance, param0)  // attempting to pass a Provider<String> instead of Provider<Lazy<String>>
  }

  public companion object {
    @JvmStatic
    public fun create(param0: Provider<@JvmSuppressWildcards String>): InjectClass_MembersInjector =
        InjectClass_MembersInjector(param0)

    @JvmStatic
    @InjectedFieldSignature("com.squareup.test.InjectClass.lazyStringProvider")
    public fun injectLazyStringProvider(instance: InjectClass,
        lazyStringProvider: Provider<Lazy<@JvmSuppressWildcards String>>): Unit {
      instance.lazyStringProvider = lazyStringProvider
    }
  }
}

```

And what we want is this:
```kotlin
public class InjectClass_MembersInjector(
  private val param0: Provider<@JvmSuppressWildcards String>
) : MembersInjector<InjectClass> {
  public override fun injectMembers(instance: InjectClass): Unit {
    [HIDDEN]
  }

  public companion object {
    @JvmStatic
    public fun create(param0: Provider<@JvmSuppressWildcards String>): InjectClass_MembersInjector =
        InjectClass_MembersInjector(param0)

    @JvmStatic
    @InjectedFieldSignature("com.squareup.test.InjectClass.lazyStringProvider")
    public fun injectLazyStringProvider(instance: InjectClass,
        lazyStringProvider: Provider<Lazy<@JvmSuppressWildcards String>>): Unit {
      instance.lazyStringProvider = lazyStringProvider
    }
  }
}
```

### Additional contract requirements

- For a member-injected field of type `Provider<Lazy<T>>`, injection must supply a `Provider<Lazy<T>>` consistent with the `Provider<T>` supplied to the members injector. Requesting a value from the supplied provider must yield a `Lazy<T>` that resolves the corresponding `T`.
