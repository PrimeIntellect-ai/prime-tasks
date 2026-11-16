Factory generation: overloaded Provides functions
If a module has multiple overloaded `@Provides` functions with the same, only one Factory gets generated.
Dagger gives an error `Cannot have more than one binding method with the same name in a single module` for such modules.

```
@Module
object MyModule {
    @Provides fun s(): String = ""
    @Provides fun s(s: String): Int = 1
}
```
