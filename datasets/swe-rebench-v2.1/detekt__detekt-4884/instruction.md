False positive on `UnnecessaryInnerClass` calls to `this`
## Expected Behavior
If an `inner class` has a plan reference to `this`, `UnnecessaryInnerClass` should still raise an issue.

## Observed Behavior
`UnnecessaryInnerClass` does not raise an issue, even though the class could be made non-`inner`.

## Steps to Reproduce
```
@Test
fun `reports even with calls to this`() {
    val code = """
        class A {
            inner class B {
                fun foo() {
                    this
                }
            }
        }
    """.trimIndent()

    assertThat(subject.lintWithContext(env, code)).hasSize(1)
}
```

## Context
I came across this issue while working on labeled expressions in #4865 but was unable to find a resolution. [HIDDEN]

I don't have a particular use case, but it does seem to interfere with labeled expressions in some cases, e.g.
```
@Test
fun `reports irrelevant labeled expressions`() {
    val code = """
        class A {
            inner class B {
                fun inner() {
                    return Unit.apply { this@B }
                }
            }
        }
    """.trimIndent()

    assertThat(subject.lintWithContext(env, code)).hasSize(1)
}
```

this test will fail, not because of labeled expression as per #4865 but because of the use of `this@B`, even though that doesn't require `B` to be `inner`.

## Your Environment
* current main branch (`fcd9c48159685fc049da6e6d2b3a77db3aea00bd`)
