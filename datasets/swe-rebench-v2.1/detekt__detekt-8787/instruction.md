False negative on `ForbiddenMethodCall`
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior
```kt
@Test
fun `should report property getters call used without property`() {
    val code = """
        fun foo() = run {
            val calendar = java.util.Calendar.getInstance()
            calendar.firstDayOfWeek
        }
    """.trimIndent()
    val findings = ForbiddenMethodCall(
        TestConfig(METHODS to listOf("java.util.Calendar.getFirstDayOfWeek"))
    ).lintWithContext(env, code)
    assertThat(findings).hasSize(1)
}
```

above TC should pass

## Observed Behavior
Above TC is failing

## Steps to Reproduce
This is happening in the latest main branch(98e26b62f5a7aae642d30bff1124d2f2d47e8d15)


## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: Latest main branch(98e26b62f5a7aae642d30bff1124d2f2d47e8d15)
