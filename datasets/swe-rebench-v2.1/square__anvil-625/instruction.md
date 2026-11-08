Regression: generic typealias expands only one type argument
Anvil 2.4.1
Kotlin 1.7.0

Given:

    class RealType<T, U>

    typealias AliasType<X> = RealType<String, X>

    class User {
        @Inject
        lateinit var value: AliasType<Int>
    }

Anvil turns `AliasType<Int>` into `RealType<Int>` in the generated code, which causes a build error because `RealType` takes two type arguments, not one.

This is a regression from Anvil 2.4.0 and Kotlin 1.6.21 where this issue did not occur.
