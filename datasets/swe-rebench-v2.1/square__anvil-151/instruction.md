Dagger factory - Package name with a sentence case segment results in the wrong import in the generated factory
A dagger module like this
```
        package com.squareup.test

        import dagger.Module
        import dagger.Provides
        import com.uppercase.Package.Thing

        @Module
        object DaggerModule1 {
          @Provides fun provideThing(): Thing = Thing()
        }
```

generates a factory with the import to the `Package`, assuming that `Thing` is a nested class:

```
package com.squareup.test

import com.uppercase.Package
import dagger.internal.Factory
import dagger.internal.Preconditions
import kotlin.jvm.JvmStatic

object DaggerModule1_ProvideThingFactory : Factory<Package.Thing> {
  override fun get(): Package.Thing = provideThing()

  @JvmStatic
  fun create(): DaggerModule1_ProvideThingFactory = this

  @JvmStatic
  fun provideThing(): Package.Thing = Preconditions.checkNotNull(DaggerModule1.provideThing(),
      "Cannot return null from a non-@Nullable @Provides method")
}
```

This factory does not compile:
```
v: Configuring the compilation environment
e: /var/folders/34/3hpdfjvj7453gz767yc7b6j40000gn/T/Kotlin-Compilation1676785146484626793/build/anvil/com/squareup/test/DaggerModule1_ProvideThingFactory.kt: (5, 22): Packages cannot be imported
e: /var/folders/34/3hpdfjvj7453gz767yc7b6j40000gn/T/Kotlin-Compilation1676785146484626793/build/anvil/com/squareup/test/DaggerModule1_ProvideThingFactory.kt: (10, 60): Unresolved reference: Thing
e: /var/folders/34/3hpdfjvj7453gz767yc7b6j40000gn/T/Kotlin-Compilation1676785146484626793/build/anvil/com/squareup/test/DaggerModule1_ProvideThingFactory.kt: (11, 31): Unresolved reference: Thing
e: /var/folders/34/3hpdfjvj7453gz767yc7b6j40000gn/T/Kotlin-Compilation1676785146484626793/build/anvil/com/squareup/test/DaggerModule1_ProvideThingFactory.kt: (17, 31): Unresolved reference: Thing
```

Unfortunately the unconventional package is a 3rd party library that in general does not follow java conventions that are not explicitly enforced.

From the exploration, the root cause is the same as in https://github.com/square/kotlinpoet/issues/978 - `ClassName.bestGuess` does not have enough context to make the correct guess and can only rely on conventions .
