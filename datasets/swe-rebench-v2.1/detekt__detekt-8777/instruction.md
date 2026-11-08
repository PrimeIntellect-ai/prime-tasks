[CouldBeSequence] Use of `asSequence` method should not be count against the `allowedOperations`
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior
```kt
// allowed function call config is set to 2
private val subject = CouldBeSequence(TestConfig("allowedOperations" to 2))
@Test
fun `using asSequence after allowed number of operations should not trigger rule`() {
    val code = """
        fun foo() = listOf<String?>("bar")
            .mapIndexed { index, it ->  it?.let { it + "_" + index } }
            .filterNotNull()
            .asSequence()
    """.trimIndent()
    assertThat(subject.lintWithContext(env, code)).isEmpty()
}
```
above TC should pass

## Observed Behavior
Above mentioned TC is failing

## Steps to Reproduce
Run against the latest main branch

## Context
<!-- How has this issue affected you? What are you trying to accomplish? -->
<!-- Providing context helps us come up with a solution that is most useful in the real world -->

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: Latest main branch(00ccb8c3691089c40529a2ac510c1ce3ffbc23f8) of the detekt
