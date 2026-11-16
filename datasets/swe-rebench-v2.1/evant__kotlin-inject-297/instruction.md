Injection fails for class who have a dependency declared in an inherited component
Hi,

I tried to refactor my injection in a Multiplatform project, so instead of composing different components for every platform (which forced me to have different scope annotations in the common and the platform-specific components) I inherit the common component in every single platform and provide there the few dependencies that remain unprovided.

This is, IIUC, supported by [Component Inheritance](https://github.com/evant/kotlin-inject/tree/main#component-inheritance), even if the use case shown there is just testing-related.

My problem is that I think I've hit a bug, as both of these attempts fail with the same `Cannot find an @Inject constructor or provider for: A` error.

```kotlin
import me.tatarka.inject.annotations.Component
import me.tatarka.inject.annotations.Inject
import me.tatarka.inject.annotations.Provides
import me.tatarka.inject.annotations.Scope
import kotlin.annotation.Target
import kotlin.annotation.AnnotationTarget.CLASS
import kotlin.annotation.AnnotationTarget.FUNCTION
import kotlin.annotation.AnnotationTarget.PROPERTY_GETTER

@Scope
@Target(CLASS, FUNCTION, PROPERTY_GETTER)
annotation class MyScope

class A

@Inject
class B(val a: A)

@MyScope
abstract class SuperComponent {
       abstract val b : B

      @Provides abstract fun providesA() : A
}

@Component
abstract class ImplementationComponent: SuperComponent() {
       override fun providesA() = A()
}
```

```kotlin
import me.tatarka.inject.annotations.Component
import me.tatarka.inject.annotations.Inject
import me.tatarka.inject.annotations.Provides
import me.tatarka.inject.annotations.Scope
import kotlin.annotation.Target
import kotlin.annotation.AnnotationTarget.CLASS
import kotlin.annotation.AnnotationTarget.FUNCTION
import kotlin.annotation.AnnotationTarget.PROPERTY_GETTER

@Scope
@Target(CLASS, FUNCTION, PROPERTY_GETTER)
annotation class MyScope

class A

@Inject
class B(val a: A)

@MyScope
abstract class SuperComponent {
      @Provides abstract fun providesA() : A
}

@Component
abstract class ImplementationComponent: SuperComponent() {
       abstract val b : B

       override fun providesA() = A()
}
```

Ideally the first one would be my desired approach, the second one is just an attempt to create a workaround.

Am I doing something wrong here or is it a limitation of the library?
