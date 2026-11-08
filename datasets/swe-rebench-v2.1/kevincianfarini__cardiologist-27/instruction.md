2024-01-18T23:59:48 matches to wrong next local date
Failing test case:

```kt
    @Test fun matches_jan_18_2024_to_jan_19_2024() = assertEquals(
        expected = LocalDateTime(year = 2024, monthNumber = 1, dayOfMonth = 19, hour = 0, minute = 0),
        actual = LocalDateTime(year = 2024, monthNumber = 1, dayOfMonth = 18, hour = 23, minute = 59, second = 48)
            .nextMatch(atSeconds = 0..0, atMinutes = 0..0, atHours = 0..0)
    )
```
