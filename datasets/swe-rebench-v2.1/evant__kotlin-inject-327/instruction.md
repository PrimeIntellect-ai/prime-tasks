Unclear error message for scoped provider
I have a component similar to this:
```
@Scope
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY_GETTER)
annotation class AppScope

@Component
@AppScope
abstract class AndroidAppComponent
```

I meant to add a new provider from a feature module like this:
```
typealias AppScopeCoroutineScope = CoroutineScope

interface AppScopeCoroutineScopeComponent {
    @AppScope
    @Provides
    fun provideCoroutineScope(dispatcher: IoCoroutineDispatcher): AppScopeCoroutineScope {
        return CoroutineScopeScoped(...)
    }
}

@Component
@AppScope
abstract class AndroidAppComponent : AppScopeCoroutineScopeComponent
```

This fails with following error:
```
e: [ksp] @Provides with scope: com.my.package.di.AppScope cannot be provided in an unscoped component
```
This message is confusing, because it's not clear which the unscoped component is. I only found out by trial and error that this provider method is triggering the error. Removing `@AppScope` from the provider method resolves the error, but it would result in bugs and is required to be a singleton. Changing it to the following will work:
```
@AppScope
interface AppScopeCoroutineScopeComponent {
    @AppScope
    @Provides
    fun provideCoroutineScope(dispatcher: IoCoroutineDispatcher): AppScopeCoroutineScope {
        return CoroutineScopeScoped(...)
    }
}
```

However, this creates a new error:
```
e: [ksp] Cannot apply scope: com.my.package.di.AppScope
e: [ksp] /path/AndroidAppComponent.kt:11: as scope: com.my.package.di.AppScope is already applied
```

This error is surprising, because the scope is not applied twice. I needed to change my final component to this to resolve the problem:
```
@Component
abstract class AndroidAppComponent : AppScopeCoroutineScopeComponent
```
This code finally runs, but I'm afraid that it will start failing again with another interface being added.

Is this an error on my end? How do I avoid this?
