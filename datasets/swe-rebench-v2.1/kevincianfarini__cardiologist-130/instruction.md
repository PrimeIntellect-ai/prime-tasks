`2023-10-04T00:00:59.000000001` next match at seconds 1 is incorrect
The following test fails:

```kt
    @Test
    fun foo() = assertEquals(
        expected = stubDatetime.copy(minute = 1, second = 1),
        actual = stubDatetime.copy(second = 59, nanosecond = 1).nextMatch { atSeconds(1) },
    )
```

References #28
