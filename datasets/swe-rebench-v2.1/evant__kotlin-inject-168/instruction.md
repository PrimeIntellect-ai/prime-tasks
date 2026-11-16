Allow mutlithreading on kotlin native
Right now components can only be accessed on the main thread due to the `LazyMap` implementation. Need to figure out how to allow multithreading like what's available on the jvm. The solution should also work with kotlin's [new memory model](https://blog.jetbrains.com/kotlin/2021/08/try-the-new-kotlin-native-memory-manager-development-preview/).
