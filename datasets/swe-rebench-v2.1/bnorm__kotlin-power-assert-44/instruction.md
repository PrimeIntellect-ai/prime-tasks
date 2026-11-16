Compiler crash when trying to extend the plugin to kotlin.require and kotlin.check
Having power assertions on assert() is nice, but almost all the assertions in my codebase are `require` or `check`. So:

```
configure<com.bnorm.power.PowerAssertGradleExtension> {
    functions = listOf("kotlin.assert", "kotlin.test.assertTrue", "kotlin.require")
}
```

But, with Kotlin 1.5 this doesn't work, kotlinc crashes with the attached crash dump.

[dump.txt](https://github.com/bnorm/kotlin-power-assert/files/6459190/dump.txt)
