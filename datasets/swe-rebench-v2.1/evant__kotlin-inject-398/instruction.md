Question: multiple interfaces and one implementation
Hi all, I am struggling with this design: ONE adapter implements TWO interfaces. How do I define this correctly? Thanks!

```kotlin
interface UserReadPort {
    fun findAll(): Set<UserEntity>
    fun findById(id: UserId): UserEntity?
}

interface UserWritePort {
    fun addUser(user: UserEntity)
    fun remove(id: UserId)
    fun removeAll()
}

@Inject
class UserInMemoryAdapter : UserReadPort, UserWritePort { // ...

@Inject
class CreateUserUseCase(lazyUserWritePort: Lazy<UserWritePort>, lazyUserReadPort: Lazy<UserReadPort>) {
    private val userWritePort by lazyUserWritePort
    private val userReadPort by lazyUserReadPort

@Component
abstract class AppComponent(private val port: Int) {
    abstract val createUserUseCase: CreateUserUseCase

    @Provides
    fun userReadInMemoryAdapter(userReadPort: UserReadPort): UserReadPort = userReadPort

    @Provides
    fun userWriteInMemoryAdapter(userWritePort: UserWritePort): UserWritePort = userWritePort


```

produces

```
Exception in thread "main" kotlin.UninitializedPropertyAccessException: lateinit property userWritePort has not been initialized
	at InjectAppComponent$createUserUseCase$1.invoke(InjectAppComponent.kt:15)
	at InjectAppComponent$createUserUseCase$1.invoke(InjectAppComponent.kt:11)
...
```

Generated code

```kotlin

public fun KClass<AppComponent>.create(port: Int): AppComponent = InjectAppComponent(port)

public class InjectAppComponent(
  port: Int,
) : AppComponent(port) {
  override val createUserUseCase: CreateUserUseCase
    get() = CreateUserUseCase(
      lazyUserWritePort = lazy {
        run<UserWritePort> {
          lateinit var userWritePort: UserWritePort
          userWriteInMemoryAdapter(
            userWritePort = userWritePort
          ).also {
            userWritePort = it
          }
        }

      },
      lazyUserReadPort = lazy {
        run<UserReadPort> {
          lateinit var userReadPort: UserReadPort
          userReadInMemoryAdapter(
            userReadPort = userReadPort
          ).also {
            userReadPort = it
          }
        }

      }
    )
}
```

### Additional contract requirements

- When a component exposes a `Dep` whose constructor has a `Lazy<Cycle>` dependency and `Cycle` directly depends on itself, compilation must fail with output containing `Cycle detected`.
