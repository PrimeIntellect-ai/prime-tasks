class literal references like AppScope::class aren't counted as references
:moduleA declares absolutely nothing but:

```kotlin
abstract class AppScope private constructor()
```

:moduleB references that scope in an annotation, *with a wildcard import*:

```kotlin
import com.foo.moduleA.*

@Module
@ContributesTo(AppScope::class)
object MyModule
```

The type reference visitor isn't catching type references which are inside a class literal expression, so it never sees that `AppScope::class`.  This means that it doesn't get concatenated with `com.foo.moduleA.` and isn't added to the list of possible references.

ModuleCheck will say that `:moduleA` is unused in `:moduleB`, and will recommend removing it.
