[Bug] Map.combine() does not preserve order when delegating to the nested monoid operation
This simple unit test demonstrates the issue:

```Kotlin
    @Test
    fun testArrowMapCombine() {
        val map1 = mapOf(1 to "A", 2 to "B")
        val map2 = mapOf(1 to "lpha", 2 to "eta")

        val result = map1.combine(map2, String::plus)

        assertThat(result).isEqualTo(mapOf(1 to "Alpha", 2 to "Beta"))
    }
```

It fails with:
```
expected: {1="Alpha", 2="Beta"}
but was : {1="lphaA", 2="etaB"}
```

Affected versions: 2.0.1 and 1.2.4.

Will provide a PR with a propery-based test that fails, along with a fix that makes it pass.
