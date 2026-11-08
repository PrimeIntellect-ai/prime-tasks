MissingBinding: Subcomponent cannot be provided without an @Provides-annotated method
Anvil version: 2.3.11-1-6-10

I have a common set of subcomponent hierarchies: _FirstScope_ and _SecondScope_. They are connected to different components.
At the moment, I began to receive the following compilation error:

```
/Users/trip/Documents/Projects/anvil-exxt/anvil/sample-app/build/tmp/kapt3/stubs/debug/experiment1/GroundAppComponent.java:9: error: [Dagger/MissingBinding] experiment1.FirstSubcomponent cannot be provided without an @Provides-annotated method.
public abstract interface GroundAppComponent extends experiment1.ZeroSubcomponent.ParentComponent, anvil.component.experiment1.groundappcomponent.ZeroSubcomponentA.ParentComponent {
                ^
      experiment1.FirstSubcomponent is requested at
          experiment1.FirstSubcomponent.ParentComponent.firstSubcomponent() [experiment1.GroundAppComponent → anvil.component.experiment1.groundappcomponent.ZeroSubcomponentA]
```

Full code listing leading to the error:
```
@Scope
@Retention(AnnotationRetention.RUNTIME)
annotation class SingleIn(val scope: KClass<*>)

abstract class ZeroScope private constructor()
abstract class FirstScope private constructor()
abstract class SecondScope private constructor()

@ContributesSubcomponent(
    scope = FirstScope::class,
    parentScope = ZeroScope::class
)
@SingleIn(FirstScope::class)
interface FirstSubcomponent {

    @ContributesTo(ZeroScope::class)
    interface ParentComponent {
        fun firstSubcomponent(): FirstSubcomponent
    }
}

@ContributesSubcomponent(
    scope = SecondScope::class,
    parentScope = FirstScope::class
)
@SingleIn(SecondScope::class)
interface SecondSubcomponent {

    @ContributesTo(FirstScope::class)
    interface ParentComponent {
        fun secondSubcomponent(): SecondSubcomponent
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////

@MergeComponent(ZeroScope::class)
@SingleIn(ZeroScope::class)
interface ZeroAppComponent {

    @Component.Factory
    interface Factory {
        fun create(@BindsInstance app: Application): ZeroAppComponent
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////

abstract class GroundScope private constructor()

@MergeComponent(GroundScope::class)
@SingleIn(GroundScope::class)
interface GroundAppComponent {

    @Component.Factory
    interface Factory {
        fun create(@BindsInstance app: Application): GroundAppComponent
    }
}

@ContributesSubcomponent(
    scope = ZeroScope::class,
    parentScope = GroundScope::class
)
@SingleIn(ZeroScope::class)
interface ZeroSubcomponent {

    @ContributesTo(GroundScope::class)
    interface ParentComponent {
        fun zeroSubcomponent(): ZeroSubcomponent
    }
}
```
