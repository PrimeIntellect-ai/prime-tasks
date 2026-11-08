Conflicting declarations with multiple identical overrides
Code such as the following:

```kotlin
class MyDep

interface Provisioner {

    @Provides
    fun provideMyDep() = MyDep()
}

interface Accessor1 {

    val myDep: MyDep
}

interface Accessor2 {

    val myDep: MyDep
}

@Component
interface MyComponent : Provisioner, Accessor1, Accessor2
```

Generates the following:

```kotlin
public fun KClass<MyComponent>.create(): MyComponent = InjectMyComponent()

public class InjectMyComponent : MyComponent {
  public override val myDep: MyDep
    get() = provideMyDep()

  public override val myDep: MyDep
    get() = provideMyDep()
}
```

The override should only be generated once, as this code cannot be compiled:

```
Conflicting declarations: public open val myDep: MyDep, public open val myDep: MyDep
```
