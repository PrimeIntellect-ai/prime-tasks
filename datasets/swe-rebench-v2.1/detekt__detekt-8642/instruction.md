False positive on UnnecessaryBracesAroundTrailingLambda with vararg lambdas
Already reported in issue #6593, but not fixed back in the day. Occurred to me since the update to 2.0.0-alpha.0.

Minimal reproducer:

```kotlin
import assertk.Assert
import assertk.assertThat

data class LogEvent(val message: String)

fun Assert<List<LogEvent>>.hasLogEvents(vararg matchers: Assert<LogEvent>.() -> Unit) =
    given { actual ->
        assertAll {
            actual.forEachIndexed { index, event ->
                matchers[index](assertThat(event, name = appendName(show(index, "[]"), separator = ".")))
            }
        }
    }

assertThat(listOf(LogEvent("foo")))
    .hasLogEvents({
        TODO("first assertion for first event")
    })

assertThat(listOf(LogEvent("foo"), LogEvent("bar")))
    .hasLogEvents({
        TODO("first assertion for first event")
    },
    {
        TODO("first assertion for second event")
    })
```
