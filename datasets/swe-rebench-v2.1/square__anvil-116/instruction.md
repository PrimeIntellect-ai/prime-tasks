Support named import
The following class is processed successfully by Dagger compiler but not by Anvil
```
package com.squareup.test

import dagger.Module
import dagger.Provides
import java.lang.Runnable as NamedRunnable

@Module
object DaggerModule1 {
    @Provides fun provideRunner(): NamedRunnable = NamedRunnable {}
}
```
