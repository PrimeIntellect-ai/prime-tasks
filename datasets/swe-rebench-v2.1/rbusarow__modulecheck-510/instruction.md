Resource declarations are "unused" in intermediate module if consumed via that module's R class
#### Given:

`android.nonTransitiveRClass` is `false` in `gradle.properties`
Module `:lib1` declares string `R.string.string_from_lib1`
Module `:lib2` does not declare anything, but has `:lib1` as a dependency

`:lib3` depends upon both `:lib1` and `:lib2`, and has this source:
```kotlin
package com.modulecheck.lib3

import com.modulecheck.lib2.R

val string = R.string.string_from_lib1
```

#### Expected:

No issues should be found.

#### Actual:

ModuleCheck says that `:lib2` doesn't use `:lib1` since its only use is in the generated `com.modulecheck.lib2.R` class.
```
:lib2
      ​configuration​    dependency​    name            ​    source​    build file
   ✔  ​api          ​    :lib1     ​    unusedDependency​          ​    [...]/lib2/build.gradle.kts: (7, 3):

ModuleCheck found 1 issue in 0.89 seconds.
```

This is pretty similar to the problem posed by Anvil (#223).
- We can't just look at non-generated code to determine if the module is used.
  - This is what's causing this bug.
- We can't just assume that everything being generated is being used.
  - This is what's currently happening with Anvil -- again see #223.


In this case, `:lib2` is using `:lib1` in order to generate `com.modulecheck.lib2.R.string.string_from_lib1`.  If there are no references to that particular string from the `:lib2` namespace, then it should be "unused".
