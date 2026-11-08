USE_DATA_CLASS: False positive for Annotations
I have this annotation:
```kotlin
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class NavGraphDestination(
    val name: String = Defaults.NULL,
    val routePrefix: String = Defaults.NULL,
    val deepLink: Boolean = false,
) {
    object Defaults {
        const val NULL = "@null"
    }
}
```
And Diktat complains that
```
There are 1 unfixed errors:
Error on line: 3, column: 1 cannot be fixed automatically
[USE_DATA_CLASS] this class can be converted to a data class: NavGraphDestination
java.lang.AssertionError: There are 1 unfixed errors:
```

[HIDDEN]

https://github.com/saveourtool/diktat/blob/54c8ccefc3009b8dd2a493c30590168318765b89/diktat-rules/src/main/kotlin/org/cqfn/diktat/ruleset/rules/chapter6/classes/DataClassesRule.kt#L46

I'm having this with Diktat 1.2.1. Let me know if you need more info.
