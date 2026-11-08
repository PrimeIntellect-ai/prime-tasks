Support for @Inject with generic types
Currently processing:
```
class InjectClass<T> @Inject constructor(val provider: Provider<T>)
```
is valid in Dagger but throws an error in Anvil
