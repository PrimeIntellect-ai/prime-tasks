`WRONG_INDENTATION`: running `mvn diktat:fix` adds whitespace to string literals
Consider this code fragment:

```kotlin
    @Test
    fun `checking that suppression with ignore everything works`() {
        val code =
                """
                    @Suppress("diktat")
                    fun foo() {
                        val a = 1
                    }
                """.trimIndent()
        lintMethod(code)
    }
```

Whenever the code doesn't match the settings of DiKTat (i.e., in the above example, the body of the `code` expression uses _continuation indent_ while `extendedIndentAfterOperators` is false), running `mvn diktat:fix` is expected to re-format the code.

While doing so (particularly, when `WRONG_INDENTATION` check is **on**), it sometimes adds extra whitespace **around** and **within** string literals, i. e.

```kotlin
                    @Suppress("diktat")
```

may become

```kotlin
                    @Suppress(    "    diktat    "    )
```

Moreover, the operation is not idempotent, so running `mvn diktat:fix` consecutively yet increases the amount of whitespace.

Sometimes excessively long lines get wrapped, and this may even result in non-compilable code:

```kotlin
                    @Suppress(    "    diktat
    "    )
```

Screenshot:

![](https://user-images.githubusercontent.com/58667063/171014226-54696a6a-319d-42e8-9b14-b74fd30ee8f5.png)

Originally from [this comment](https://github.com/saveourtool/diktat/issues/1330#issue-1252828874).
